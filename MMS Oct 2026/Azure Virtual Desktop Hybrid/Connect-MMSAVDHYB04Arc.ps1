#requires -Version 5.1

<#
.SYNOPSIS
Checks or manually connects only MMS-AVDHYB-04 to Azure Arc.
.DESCRIPTION
Runs on the exact VMID 125 guest. Check is local/read-only. An explicit
Register action will use Microsoft's staged, signed MSI and a device-code sign-in.
No AVD registration is performed by this script.
.EXAMPLE
.\Connect-MMSAVDHYB04Arc.ps1
.EXAMPLE
.\Connect-MMSAVDHYB04Arc.ps1 -Action Register -WhatIf
.EXAMPLE
.\Connect-MMSAVDHYB04Arc.ps1 -Action Register -Confirm
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param([ValidateSet('Check','Register')][string]$Action='Check')

function Get-Arc04Target([string]$Name, [string]$Uuid) {
    if ($Name -ne 'MMS-AVDHYB-04') { throw 'Hostname is not on the Arc onboarding allowlist.' }
    if ($Uuid -ne '49563447-D6F9-44AA-B7A9-C240FF2D8C2F') { throw 'SMBIOS UUID does not match VMID 125.' }
    $subscription='e6ab1306-dfc4-4975-9f15-1df30c4699e2'
    $group='rg-MMS-AVDHybrid-UnderTheHood'
    return [pscustomobject]@{
        Name=$Name;Uuid=$Uuid;Vmid=125;Subscription=$subscription
        Tenant='280bf3c4-6674-481d-907a-2e873c775e72';ResourceGroup=$group;Location='westus3'
        ArcId=('/subscriptions/'+$subscription+'/resourceGroups/'+$group+'/providers/Microsoft.HybridCompute/machines/'+$Name)
        MsiPath='C:\Scripts\AzureConnectedMachineAgent.msi'
        MsiSha256='5B7D70E913DFA73B9277F157A62955F0EB0917B00A10CAA76D424B78934A1319'
    }
}

function Assert-Arc04Local($Evidence, $Target) {
    if ($Evidence.Name -ne $Target.Name -or $Evidence.Uuid -ne $Target.Uuid) { throw 'Guest hostname/UUID changed during preflight.' }
    if (-not $Evidence.Joined -or $Evidence.Domain -ne 'AD.Mauvlan.Net' -or -not $Evidence.SecureChannel) {
        throw 'Expected AD domain membership and a working secure channel.'
    }
    if ($Evidence.AzureAdJoined -ne 'YES' -or $Evidence.DomainJoined -ne 'YES' -or $Evidence.TenantId -ne $Target.Tenant) {
        throw 'Expected hybrid Entra join to the named tenant.'
    }
    $msi=$Evidence.Msi
    if (-not $msi -or -not $msi.Exists -or $msi.Size -lt 5000000 -or $msi.Signature -ne 'Valid' -or
        $msi.Signer -notmatch 'Microsoft Corporation' -or $msi.Sha256 -ne $Target.MsiSha256) {
        throw 'Staged Arc installer signature, size or hash could not be verified.'
    }
    if ($Evidence.Arc) {
        $arc=$Evidence.Arc
        if ($arc.ResourceId -and $arc.ResourceId -ne $Target.ArcId) { throw 'Arc agent is bound to a foreign resource.' }
        if ($arc.VmUuid -and $arc.VmUuid -ne $Target.Uuid) { throw 'Arc agent VM UUID mismatch.' }
        if ($arc.TenantId -and $arc.TenantId -ne $Target.Tenant) { throw 'Arc agent tenant mismatch.' }
        if ($arc.Status -eq 'Connected') {
            if ($arc.ResourceId -ne $Target.ArcId -or $arc.VmUuid -ne $Target.Uuid) { throw 'Connected Arc identity is incomplete.' }
            return [pscustomobject]@{State='AlreadyConnected';Name=$Target.Name;Vmid=$Target.Vmid;ArcId=$Target.ArcId;InstallRequired=$false}
        }
        if ($arc.Status -ne 'Disconnected') { throw 'Unexpected Arc agent status; inspect before retrying.' }
    }
    return [pscustomobject]@{State='ReadyForManualConnection';Name=$Target.Name;Vmid=$Target.Vmid;ArcId=$Target.ArcId;InstallRequired=($null -eq $Evidence.Arc)}
}

function Test-Arc04Elevation {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-Arc04Native([string]$Path, [string[]]$Arguments) {
    try {
        $output = & $Path @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Native command returned nonzero' }
        return $output
    } catch { throw 'Local native read failed; inspect this host before connecting.' }
}

function Get-Arc04LocalEvidence {
    # -Confirm on Register must apply only to the one Arc connection decision,
    # not to read-only CIM import and secure-channel checks.
    $priorConfirm=$ConfirmPreference
    try {
    $ConfirmPreference='None'
    # CIM's module import defines local aliases; inherit WhatIf for the actual
    # preflight but clear it only while loading this built-in local module.
    $priorWhatIf=$WhatIfPreference
    try {
        $WhatIfPreference=$false
        Import-Module -Name CimCmdlets -ErrorAction Stop
    } finally { $WhatIfPreference=$priorWhatIf }
    $computer=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $product=Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
    $target=Get-Arc04Target $computer.Name $product.UUID
    $msi=$target.MsiPath
    if (-not (Test-Path -LiteralPath $msi -ErrorAction Stop)) { throw 'Staged Arc MSI is missing.' }
    $item=Get-Item -LiteralPath $msi -ErrorAction Stop
    $signature=Get-AuthenticodeSignature -FilePath $msi
    $hash=Get-FileHash -Path $msi -Algorithm SHA256 -ErrorAction Stop
    $dsregExe=Join-Path $env:SystemRoot 'System32\dsregcmd.exe'
    $dsreg=Read-Arc04Native $dsregExe @('/status')
    $join=@{}
    foreach($name in @('AzureAdJoined','DomainJoined','TenantId')) {
        $m=[regex]::Match($dsreg,('(?im)^\s*'+[regex]::Escape($name)+'\s*:\s*(\S+)'))
        $join[$name]=if($m.Success){$m.Groups[1].Value}else{''}
    }
    $arcExe=Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    $service=Get-Service -Name himds -ErrorAction SilentlyContinue
    $arc=$null
    if($service) {
        if(-not(Test-Path -LiteralPath $arcExe -ErrorAction Stop)) {throw 'Arc service exists but azcmagent executable is missing.'}
        $data=Read-Arc04Native $arcExe @('show','--json') | ConvertFrom-Json -ErrorAction Stop
        $arc=[pscustomobject]@{Status=$data.status;ResourceId=$data.resourceId;VmUuid=$data.vmUuid;TenantId=$data.tenantId}
    } elseif(Test-Path -LiteralPath $arcExe -ErrorAction Stop) {throw 'Arc executable exists without its service; inspect incomplete installation.'}
    return [pscustomobject]@{
        Name=$computer.Name;Uuid=$product.UUID;Domain=$computer.Domain;Joined=$computer.PartOfDomain
        SecureChannel=(Test-ComputerSecureChannel -WhatIf:$false -ErrorAction Stop)
        AzureAdJoined=$join.AzureAdJoined;DomainJoined=$join.DomainJoined;TenantId=$join.TenantId
        Msi=[pscustomobject]@{Exists=$true;Size=$item.Length;Signature=$signature.Status.ToString()
            Signer=$signature.SignerCertificate.Subject;Sha256=$hash.Hash};Arc=$arc
    }
    } finally { $ConfirmPreference=$priorConfirm }
}

function Install-Arc04Agent($Target) {
    # Recheck the bytes immediately before installing; staging-time evidence can age.
    $msi=$Target.MsiPath
    $item=Get-Item -LiteralPath $msi -ErrorAction Stop
    $signature=Get-AuthenticodeSignature -FilePath $msi
    $hash=Get-FileHash -Path $msi -Algorithm SHA256 -ErrorAction Stop
    if($item.Length -lt 5000000 -or $signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation' -or $hash.Hash -ne $Target.MsiSha256) {
        throw 'The staged Arc installer changed or cannot be trusted; nothing was installed.'
    }
    $log='C:\Windows\Temp\MMS-Arc-125-install.log'
    $process=Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i',$msi,'/qn','/norestart','/l*v',$log) -Wait -PassThru -ErrorAction Stop
    if($process.ExitCode -eq 3010) { throw 'Arc MSI requires a reboot. No reboot was started; inspect the installer log and reboot deliberately before retrying.' }
    if($process.ExitCode -ne 0) { throw ('Arc MSI failed with exit code '+$process.ExitCode+'. Inspect '+$log) }
    $service=Get-Service -Name himds -ErrorAction Stop
    if($service.Status -ne 'Running' -or -not(Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'))) {
        throw 'Arc MSI returned success but the agent service/executable is not ready; inspect before connecting.'
    }
}

function Invoke-Arc04ConnectNative([string]$Exe, [string[]]$Arguments) {
    # Stream the device-code instructions to the human at the console; do not
    # capture them, transcribe them into logs, or accept them in chat.
    $prior=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        & $Exe @Arguments 2>&1 | Out-Host
        return [int]$LASTEXITCODE
    } finally { $ErrorActionPreference=$prior }
}

function Connect-Arc04($Target) {
    $exe=Join-Path $env:ProgramFiles 'AzureConnectedMachineAgent\azcmagent.exe'
    if(-not(Test-Path -LiteralPath $exe -ErrorAction Stop)) { throw 'Arc agent executable is absent; inspect installation.' }
    $arguments=@('connect','--use-device-code','--subscription-id',$Target.Subscription,
        '--resource-group',$Target.ResourceGroup,'--location',$Target.Location,
        '--tenant-id',$Target.Tenant,'--cloud','AzureCloud','--resource-name',$Target.Name,
        '--tags','session=MMS-AVDHybrid-UnderTheHood,vmid=125,onboarding=manual')
    $code=Invoke-Arc04ConnectNative $exe $arguments
    if($code -ne 0) { throw ('Arc connect failed with exit code '+$code+'; inspect the host and Azure before retrying.') }
    $show=Read-Arc04Native $exe @('show','--json') | ConvertFrom-Json -ErrorAction Stop
    if($show.status -ne 'Connected' -or $show.resourceId -ne $Target.ArcId -or
        $show.vmUuid -ne $Target.Uuid -or $show.tenantId -ne $Target.Tenant -or
        $show.subscriptionId -ne $Target.Subscription -or $show.resourceGroup -ne $Target.ResourceGroup -or
        $show.location -ne $Target.Location -or $show.resourceName -ne $Target.Name) {
        throw 'Arc connect returned success but local agent identity is not the exact target; inspect Azure before retrying.'
    }
    return [pscustomobject]@{State='ConnectedLocal';Name=$Target.Name;Vmid=$Target.Vmid;ArcId=$Target.ArcId
        Detail='Local Arc agent reports Connected. Verify the exact resource in Azure portal; no AVD registration was performed.'}
}

function Invoke-Arc04 {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([ValidateSet('Check','Register')][string]$Action='Check')
    $ErrorActionPreference='Stop'
    if($Action -eq 'Register' -and -not $WhatIfPreference -and -not (Test-Arc04Elevation)) {
        throw 'Arc registration requires elevated Windows PowerShell (Run as administrator). No installation or connection was attempted.'
    }
    $evidence=Get-Arc04LocalEvidence
    $target=Get-Arc04Target $evidence.Name $evidence.Uuid
    $state=Assert-Arc04Local $evidence $target
    if($Action -eq 'Check') {
        return [pscustomobject]@{State=$state.State;Name=$target.Name;Vmid=$target.Vmid;ArcId=$target.ArcId
            Detail='Local host, hybrid join and pinned Microsoft installer checked. Azure was not queried; nothing was installed or connected.'}
    }
    if($WhatIfPreference) {
        return [pscustomobject]@{State='PlanOnly';Name=$target.Name;Vmid=$target.Vmid;ArcId=$target.ArcId
            Steps=@('Install the staged signed Arc agent MSI if needed','azcmagent connect to this exact resource using an interactive device-code sign-in')
            Detail='Preview only: no install, sign-in or Azure read/write occurred.'}
    }
    if($state.State -eq 'AlreadyConnected') { throw 'This exact host is already Arc-connected; registration will not run again.' }
    if($PSCmdlet.ShouldProcess($target.ArcId,'Install the pinned Arc agent MSI if needed, then connect this host to Azure Arc')) {
        if($state.InstallRequired) { Install-Arc04Agent $target }
        $fresh=Get-Arc04LocalEvidence
        $freshState=Assert-Arc04Local $fresh $target
        if($freshState.State -ne 'ReadyForManualConnection') {throw 'Local identity or Arc state changed before connection; refusing to proceed.'}
        return (Connect-Arc04 $target)
    }
}

Invoke-Arc04 -Action $Action -WhatIf:$WhatIfPreference
