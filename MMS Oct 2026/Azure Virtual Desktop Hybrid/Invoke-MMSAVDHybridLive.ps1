#requires -Version 5.1

<#
.SYNOPSIS
Stages/checks or explicitly starts MMS Live AVD Hybrid registration on hosts 01/02.
.DESCRIPTION
Run in elevated Windows PowerShell 5.1 on the actual Live guest. Copy this SAME
file to both hosts. Default Check reads local state only; it neither loads Az
nor proves Azure absence. Any WhatIf is also local-only and never signs in.

Register is the only mutating action. It uses Az.Accounts device authentication,
disables context autosave for this process, and signs in with Scope Process.
It checks the exact subscription tenant, Arc resource/UUID/status, both pools and
all extension pages before rotating ONLY the Live pool key (UTC+4h) and issuing
a raw REST PUT for ONLY this guest's AVD Arc extension. The host-pool UAMI Reader
grant is pre-staged; this script does not create identities or role assignments.

Register returns after ARM accepts the extension request, plus one immediate
exact-target GET. It does not wait for extension completion or broker Available.
Use Status in the SAME PowerShell process; Status only uses an existing matching
context and never prompts for sign-in. Exit/close that process when finished.

Ready host 03 and every other hostname/UUID pair are forbidden. Any local AVD
service/key/extension evidence blocks Check/Register, including stale evidence:
inspect manually rather than deleting it or forcing an overwrite. Azure 403,
failed reads and malformed/paginated responses are NOT treated as absence.

Run Register sequentially, not concurrently on both guests: each run rotates a
shared Live pool token. Let the prior extension finish consuming it (preferably
Succeeded) before rotating again. No automatic retry, removal, rollback, reboot,
module install or token cleanup is performed. After partial failure use Status;
do not blindly rerun or delete existing extension/registration to bypass guards.

No real token is embedded, printed or written to disk. Raw ARM error bodies are
suppressed, including on failed requests. Do not enable PowerShell step tracing,
SDK HTTP tracing or inspect/serialize in-memory secret variables while running.
Reference clearing is best-effort, not managed-memory zeroization. This does not
undo pre-existing Azure sign-ins/caches or machine-wide logging policies.
.EXAMPLE
.\Invoke-MMSAVDHybridLive.ps1
Local Check only; safe to run during staging.
.EXAMPLE
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -WhatIf
Local-only plan; no authentication, Azure requests or changes.
.EXAMPLE
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -Confirm
Human-only on-stage operation. Complete the device prompt yourself, not in chat.
.EXAMPLE
.\Invoke-MMSAVDHybridLive.ps1 -Action Status | Format-List
Read-only follow-up in the same signed-in PowerShell process. Extension Succeeded
and broker Available are separate; allow up to 15 minutes and test Windows App.
.NOTES
Needs Az.Accounts (not Azure CLI/Az.DesktopVirtualization/Az.ConnectedMachine)
only for Register/Status. Operator needs read access to subscription/machines/
extensions/both pools and write/action rights for Live registrationInfo,
retrieveRegistrationToken and this machine's extension. No RBAC changes here.
VMID is an operator label; SMBIOS + Arc VM UUID checks bind the actual guest.
Sources:
https://learn.microsoft.com/azure/virtual-desktop/deploy-azure-virtual-desktop-hybrid
https://learn.microsoft.com/rest/api/desktopvirtualization/host-pools/retrieve-registration-token?view=rest-desktopvirtualization-2025-10-10
https://learn.microsoft.com/rest/api/hybridcompute/machine-extensions/create-or-update?view=rest-hybridcompute-2024-07-10
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidateSet('Check','Register','Status')][string]$Action = 'Check')

function Get-MmsTarget([string]$Name, [string]$Uuid) {
    $ids = @{
        'MMS-AVDHYB-01' = @('81BCC02C-50E3-4ECF-8A86-D5180C42CC7B',122)
        'MMS-AVDHYB-02' = @('45DA37B2-1BE2-494D-9142-7B6FC78B564A',123)
    }
    if (-not $ids.ContainsKey($Name)) { throw 'Host is not on the Live allowlist; Ready and all other hosts are forbidden.' }
    if ($Uuid -ne $ids[$Name][0]) { throw 'SMBIOS UUID does not match the allowlisted Live VM UUID.' }
    $subscription = 'e6ab1306-dfc4-4975-9f15-1df30c4699e2'
    $base = '/subscriptions/' + $subscription + '/resourceGroups/rg-MMS-AVDHybrid-UnderTheHood/providers/'
    return [pscustomobject]@{
        Name=$Name; Uuid=$ids[$Name][0]; Vmid=$ids[$Name][1]
        Subscription=$subscription; Tenant='280bf3c4-6674-481d-907a-2e873c775e72'
        ArcId=($base + 'Microsoft.HybridCompute/machines/' + $Name)
        LiveId=($base + 'Microsoft.DesktopVirtualization/hostPools/hp-MMS-AVDHybrid-UnderTheHood')
        ReadyId=($base + 'Microsoft.DesktopVirtualization/hostPools/hp-MMS-AVDHybrid-UnderTheHood-Ready')
        Location='westus3'
    }
}

function Assert-MmsLocal($Evidence, [switch]$AllowRegistered) {
    $target = Get-MmsTarget $Evidence.Name $Evidence.Uuid
    if (-not $Evidence.PartOfDomain -or $Evidence.Domain -ne 'AD.Mauvlan.Net' -or -not $Evidence.SecureChannel) {
        throw 'Expected AD.Mauvlan.Net domain membership and a working secure channel.'
    }
    foreach ($pattern in @('(?im)^\s*AzureAdJoined\s*:\s*YES\s*$','(?im)^\s*DomainJoined\s*:\s*YES\s*$',('(?im)^\s*TenantId\s*:\s*' + [regex]::Escape($target.Tenant) + '\s*$'))) {
        if ($Evidence.JoinText -notmatch $pattern) { throw 'Guest hybrid join / tenant could not be verified with dsregcmd.' }
    }
    if ($Evidence.Arc.status -ne 'Connected') { throw 'Local Azure Arc agent must report Connected.' }
    if ($Evidence.Arc.resourceId -ne $target.ArcId) { throw 'Local Arc resource ID does not match this Live guest.' }
    if ($Evidence.Arc.vmUuid -ne $target.Uuid) { throw 'Local Arc VM UUID does not match SMBIOS.' }
    if ($Evidence.Arc.tenantId -ne $target.Tenant) { throw 'Local Arc tenant does not match.' }
    if ($Evidence.AvdPresent -and -not $AllowRegistered) { throw 'AVD agent/registration/extension already present locally; refusing to register again.' }
    return $target
}

function Read-MmsNative([string]$Path, [string[]]$Arguments) {
    # Never include native output in errors. No redirection to a file.
    try {
        $text = & $Path @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Nonzero native exit' }
        return $text
    } catch { throw 'Local read command failed.' }
}

function Get-MmsLocalEvidence {
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $product = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
    # Fail closed on the guest binding before executing anything else.
    $null = Get-MmsTarget $computer.Name $product.UUID
    $arcExe = Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    $dsregExe = Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
    $arc = Read-MmsNative $arcExe @('show','--json') | ConvertFrom-Json -ErrorAction Stop
    $join = Read-MmsNative $dsregExe @('/status')
    $present = @((Get-Service -ErrorAction Stop) | Where-Object { $_.Name -in @('RDAgentBootLoader','RDAgent') }).Count -gt 0
    foreach ($path in @('HKLM:\SOFTWARE\Microsoft\RDInfraAgent','HKLM:\SOFTWARE\WOW6432Node\Microsoft\RDInfraAgent',
        'C:\Packages\Plugins\Microsoft.AzureVirtualDesktop.CloudDeviceExtension',
        'C:\ProgramData\GuestConfig\extension_logs\Microsoft.AzureVirtualDesktop.CloudDeviceExtension')) {
        if (Test-Path -LiteralPath $path -ErrorAction Stop) { $present = $true }
    }
    return [pscustomobject]@{Name=$computer.Name;Uuid=$product.UUID;Domain=$computer.Domain
        PartOfDomain=$computer.PartOfDomain; SecureChannel=(Test-ComputerSecureChannel -WhatIf:$false -ErrorAction Stop)
        Arc=$arc;JoinText=$join;AvdPresent=$present}
}

function Open-MmsAzure($Target, [switch]$Interactive) {
    Import-Module Az.Accounts -ErrorAction Stop
    if ($Interactive) {
        $null = Disable-AzContextAutosave -Scope Process -ErrorAction Stop
        # Human-only prompt, never used by Check/WhatIf/Status.
        Connect-AzAccount -UseDeviceAuthentication -Tenant $Target.Tenant -Subscription $Target.Subscription -Scope Process -ErrorAction Stop | Out-Host
        $context = Get-AzContext -ErrorAction Stop
    } else { $context = Get-AzContext -ErrorAction Stop }
    if (-not $context -or $context.Tenant.Id -ne $Target.Tenant -or $context.Subscription.Id -ne $Target.Subscription) {
        throw 'No matching existing Azure context. Status never signs in; run it in the same process as Register.'
    }
    return $context
}

function Invoke-MmsArm {
    param([ValidateSet('GET','PATCH','POST','PUT')][string]$Method, [string]$Path, $Context, [string]$Payload)
    # Do not forward raw exceptions or response bodies: PATCH/POST may contain tokens.
    $argsMap = @{Method=$Method;Path=$Path;DefaultProfile=$Context;ErrorAction='Stop';Verbose=$false;Debug=$false}
    if ($PSBoundParameters.ContainsKey('Payload')) { $argsMap.Payload=$Payload }
    try { $response = Invoke-AzRestMethod @argsMap }
    catch { throw ('ARM ' + $Method + ' request failed; response suppressed for secret safety.') }
    if ([int]$response.StatusCode -notin @(200,201,202,204)) { throw ('ARM ' + $Method + ' failed (HTTP ' + $response.StatusCode + ').') }
    return $response
}

function Read-MmsCollection([string]$Path, $Context) {
    $root = $Path.Split('?')[0]
    $seen = @{}
    while ($Path) {
        if ($seen.ContainsKey($Path)) { throw 'ARM nextLink pagination loop refused.' }
        $seen[$Path]=$true
        $page = (Invoke-MmsArm -Method GET -Path $Path -Context $Context).Content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $page.value) { throw 'Malformed ARM collection; missing value array.' }
        foreach ($item in @($page.value)) { if ($null -ne $item) { $item } }
        $Path = [string]$page.nextLink
        if ($Path) {
            if ($Path.StartsWith('https://management.azure.com/',[StringComparison]::OrdinalIgnoreCase)) { $Path=$Path.Substring('https://management.azure.com'.Length) }
            if (-not $Path.StartsWith($root+'?',[StringComparison]::OrdinalIgnoreCase)) { throw 'Foreign ARM nextLink refused.' }
        }
    }
}

function Read-MmsCloud($Target, $Context) {
    $sub = (Invoke-MmsArm -Method GET -Path ('/subscriptions/' + $Target.Subscription + '?api-version=2022-12-01') -Context $Context).Content | ConvertFrom-Json -ErrorAction Stop
    if ($sub.tenantId -ne $Target.Tenant -or $sub.subscriptionId -ne $Target.Subscription) { throw 'ARM subscription tenant/identity verification failed.' }
    $machine = (Invoke-MmsArm -Method GET -Path ($Target.ArcId+'?api-version=2024-07-10') -Context $Context).Content | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{Machine=$machine
        Extensions=@(Read-MmsCollection ($Target.ArcId+'/extensions?api-version=2024-07-10') $Context)
        LiveHosts=@(Read-MmsCollection ($Target.LiveId+'/sessionHosts?api-version=2025-10-10') $Context)
        ReadyHosts=@(Read-MmsCollection ($Target.ReadyId+'/sessionHosts?api-version=2025-10-10') $Context)}
}

function Test-MmsHostMatch($Target, $HostRecord) {
    $shortName = ([string]$HostRecord.name).Split('/')[-1].Split('.')[0]
    return ($shortName -eq $Target.Name -or $HostRecord.properties.resourceId -eq $Target.ArcId -or
        $HostRecord.properties.virtualMachineId -eq $Target.Uuid -or $HostRecord.properties.vmId -eq $Target.Uuid)
}

function Assert-MmsCloud($Target, $Cloud, [switch]$AllowRegistered) {
    if ($Cloud.Machine.id -ne $Target.ArcId) { throw 'ARM Arc resource ID mismatch.' }
    if ($Cloud.Machine.properties.detectedProperties.vmuuidEsu -ne $Target.Uuid) { throw 'ARM Arc VM UUID mismatch.' }
    if ($Cloud.Machine.properties.status -ne 'Connected') { throw 'ARM Arc machine must be Connected.' }
    if ($Cloud.Machine.location -ne $Target.Location) { throw 'ARM Arc location mismatch.' }
    if (-not $AllowRegistered) {
        foreach ($ext in @($Cloud.Extensions)) {
            if (-not $ext.name) { throw 'Malformed Arc extension record; cannot prove extension absent.' }
            if (([string]$ext.name).Split('/')[-1] -eq 'Microsoft.AzureVirtualDesktop.CloudDeviceExtension' -or
                $ext.properties.type -eq 'CloudDeviceExtension') { throw 'AVD Arc extension already present, regardless of provisioning state; refusing overwrite.' }
        }
        foreach ($hostRecord in (@($Cloud.LiveHosts) + @($Cloud.ReadyHosts))) {
            if (-not $hostRecord.name) { throw 'Malformed session host record; cannot prove registration absent.' }
            if (Test-MmsHostMatch $Target $hostRecord) { throw 'This guest is already registered in Live or Ready; refusing registration.' }
        }
    }
}

function Submit-MmsRegistration($Target, $Context) {
    # Re-read local + Azure guards immediately before the first write, even after login/confirmation.
    $current = Assert-MmsLocal (Get-MmsLocalEvidence)
    if ($current.ArcId -ne $Target.ArcId) { throw 'Guest identity changed before submission.' }
    Assert-MmsCloud $Target (Read-MmsCloud $Target $Context)
    $extensionId = $Target.ArcId+'/extensions/Microsoft.AzureVirtualDesktop.CloudDeviceExtension'
    $expires = [DateTimeOffset]::UtcNow.AddHours(4)
    $patch = @{properties=@{registrationInfo=@{expirationTime=$expires.ToString('o');registrationTokenOperation='Update'}}} | ConvertTo-Json -Depth 6 -Compress
    # PATCH response may contain registrationInfo.token: capture/discard, never output.
    $null = Invoke-MmsArm -Method PATCH -Path ($Target.LiveId+'?api-version=2025-10-10') -Context $Context -Payload $patch
    $raw = $null; $info = $null; $token = $null; $payload = $null; $extension = $null
    try {
        try {
            $raw = Invoke-MmsArm -Method POST -Path ($Target.LiveId+'/retrieveRegistrationToken?api-version=2025-10-10') -Context $Context
            $info = $raw.Content | ConvertFrom-Json -ErrorAction Stop
            $token = [string]$info.token
            if ([string]::IsNullOrWhiteSpace($token)) { throw 'Missing registration token' }
            if ($info.expirationTime -is [DateTime]) { $actualExpiry = [DateTimeOffset]$info.expirationTime }
            else { $actualExpiry = [DateTimeOffset]::Parse([string]$info.expirationTime) }
            if ([Math]::Abs(($actualExpiry - $expires).TotalMinutes) -gt 1) { throw 'Registration expiry readback mismatch' }
        } catch { throw 'Live registration token retrieval failed. Live token may already have rotated; no extension request was sent.' }
        $extension = @{location=$Target.Location;properties=@{
            publisher='Microsoft.AzureVirtualDesktop';type='CloudDeviceExtension';typeHandlerVersion='1.0';autoUpgradeMinorVersion=$true
            settings=@{isCloudDevice=$false};protectedSettings=@{registrationToken=$token}
        }}
        $payload = $extension | ConvertTo-Json -Depth 8 -Compress
        $accepted = Invoke-MmsArm -Method PUT -Path ($extensionId+'?api-version=2024-07-10') -Context $Context -Payload $payload
        $code = [int]$accepted.StatusCode
        # One immediate exact-target readback only; never poll the long-running operation.
        $readBack = 'Unconfirmed; use Status'
        try {
            $read = (Invoke-MmsArm -Method GET -Path ($extensionId+'?api-version=2024-07-10') -Context $Context).Content | ConvertFrom-Json -ErrorAction Stop
            if ($read.id -eq $extensionId -and $read.properties.provisioningState) { $readBack=[string]$read.properties.provisioningState }
        } catch { $readBack='Unconfirmed (read failed); use Status' }
        return [pscustomobject]@{State='ExtensionAccepted';Machine=$Target.Name;HttpStatus=$code;ReadBack=$readBack
            Detail='Extension request accepted, NOT proof of AVD registration/Available. Run -Action Status in this PowerShell process. Allow up to 15 minutes after extension Succeeded; verify Windows App separately.'}
    } finally {
        # Best-effort reference clearing, not a promise of managed-memory zeroization.
        $raw=$null; $info=$null; $token=$null; $payload=$null; $extension=$null
    }
}

function Invoke-MmsLive {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([ValidateSet('Check','Register','Status')][string]$Action='Check')
    $ErrorActionPreference = 'Stop'
    $evidence = Get-MmsLocalEvidence
    $target = Assert-MmsLocal $evidence -AllowRegistered:($Action -eq 'Status')
    if ($Action -eq 'Check' -or $WhatIfPreference) {
        $state = if ($WhatIfPreference) { 'PlanOnly' } else { 'LocallyStaged' }
        return [pscustomobject]@{State=$state; Machine=$target.Name; Vmid=$target.Vmid; LiveHostPool=$target.LiveId
            Detail='Local checks only; Azure state NOT checked. Register will sign in, check both pools, rotate Live token (+4h), and PUT only this Arc extension. No Ready writes.'}
    }
    $context = Open-MmsAzure $target -Interactive:($Action -eq 'Register')
    $cloud = Read-MmsCloud $target $context
    Assert-MmsCloud $target $cloud -AllowRegistered:($Action -eq 'Status')
    if ($Action -eq 'Status') {
        return [pscustomobject]@{State='AzureStatus';Machine=$target.Name;ArcStatus=$cloud.Machine.properties.status
            Extensions=@($cloud.Extensions | ForEach-Object { [pscustomobject]@{Name=$_.name;State=$_.properties.provisioningState} })
            LiveHosts=@($cloud.LiveHosts | Where-Object { Test-MmsHostMatch $target $_ } | ForEach-Object { [pscustomobject]@{Name=$_.name;Status=$_.properties.status} })
            ReadyHosts=@($cloud.ReadyHosts | Where-Object { Test-MmsHostMatch $target $_ } | ForEach-Object { [pscustomobject]@{Name=$_.name;Status=$_.properties.status} })
            Detail='Read-only status; Available is broker status, not a Windows App sign-in test.'}
    }
    if ($PSCmdlet.ShouldProcess($target.ArcId, 'Rotate Live registration token (UTC+4h) and create AVD Hybrid extension')) {
        return (Submit-MmsRegistration $target $context)
    }
}

Invoke-MmsLive -Action $Action -WhatIf:$WhatIfPreference
