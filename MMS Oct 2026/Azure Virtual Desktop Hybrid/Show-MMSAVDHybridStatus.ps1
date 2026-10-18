#requires -Version 5.1
<#+
.SYNOPSIS
  Read-only Azure Arc, Entra hybrid join, AVD Arc extension and broker status for
  the MMS AVD Hybrid demo. Does not register machines, install extensions, or
  generate/print a registration token.
.EXAMPLE
  .\Show-MMSAVDHybridStatus.ps1 -Phase Staged
.EXAMPLE
  .\Show-MMSAVDHybridStatus.ps1 -Phase AfterLive -NoColor
.NOTES
  Reuses a valid Azure CLI / Az.Accounts context or starts an interactive
  device-code login if the context is missing/expired. No password, token or
  registration key is embedded in this file. Azure CLI or Az.Accounts must
  already be installed on the computer where you run the script.
  Reader on Arc machines/extensions and AVD host pools, plus Graph Device.Read.All
  (or equivalent directory read scope), are needed. A 403 is an ERROR, not absence.
  Windows 11 here is hybrid Entra joined (Graph trustType=ServerAd); it does NOT
  need an AADLoginForWindows Arc extension. This script reports that optional
  extension separately, rather than falsely calling its absence a failure.
#>
[CmdletBinding()]
param(
    [ValidateSet('Staged','AfterLive')][string]$Phase = 'Staged',
    [string]$SubscriptionId = 'e6ab1306-dfc4-4975-9f15-1df30c4699e2',
    [string]$ResourceGroup = 'rg-MMS-AVDHybrid-UnderTheHood',
    [string]$LiveHostPool = 'hp-MMS-AVDHybrid-UnderTheHood',
    [string]$ReadyHostPool = 'hp-MMS-AVDHybrid-UnderTheHood-Ready',
    [string[]]$MachineNames = @('MMS-AVDHYB-01','MMS-AVDHYB-02','MMS-AVDHYB-03'),
    [string]$ExpectedReadyMachine = 'MMS-AVDHYB-03',
    [ValidateSet('Auto','AzureCLI','AzPowerShell')][string]$Auth = 'Auto',
    [switch]$NoLogin,
    [string]$JsonPath,
    [switch]$NoColor,
    [string]$FixturePath
)

$ErrorActionPreference = 'Stop'
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:authMode = ''
$script:fixture = $null
$armRoot = 'https://management.azure.com'
$base = '/subscriptions/' + $SubscriptionId + '/resourceGroups/' + $ResourceGroup + '/providers/'

function Field($obj, [string]$key) {
    if ($null -eq $obj) { return $null }
    if ($obj -is [System.Collections.IDictionary]) { return $obj[$key] }
    $p = $obj.PSObject.Properties[$key]
    if ($null -eq $p) { return $null }
    return $p.Value
}
function Add-Check([string]$machine,[string]$name,[string]$status,[string]$detail) {
    $script:checks.Add([pscustomobject]@{machine=$machine;name=$name;status=$status;detail=$detail})
    $fg = 'White'; $bg = 'DarkCyan'
    switch ($status) {
        'PASS'   { $bg='DarkGreen' }
        'READY'  { $bg='DarkGreen' }
        'FAIL'   { $bg='DarkRed' }
        'ERROR'  { $bg='DarkMagenta' }
        'WARN'   { $bg='DarkYellow';$fg='Black' }
        'STAGED' { $bg='DarkCyan' }
        'INFO'   { $bg='DarkBlue' }
    }
    if ($NoColor) { Write-Host ('[{0}] {1} | {2}: {3}' -f $status,$machine,$name,$detail) }
    else {
        Write-Host (' {0} ' -f $status) -BackgroundColor $bg -ForegroundColor $fg -NoNewline
        Write-Host (' {0} | {1}: {2}' -f $machine,$name,$detail)
    }
}
function Get-Http([string]$url) {
    if ($script:authMode -eq 'AzureCLI') {
        $raw = & az rest --method get --url $url -o json --only-show-errors 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw ('Azure CLI GET failed: ' + $raw.Trim()) }
        try { return ($raw | ConvertFrom-Json) }
        catch { throw ('Azure CLI returned non-JSON for ' + $url + ': ' + $_.Exception.Message) }
    }
    if ($url.StartsWith('https://management.azure.com/')) {
        $path = $url.Substring('https://management.azure.com'.Length)
        $r = Invoke-AzRestMethod -Method GET -Path $path -ErrorAction Stop
        if ($r.StatusCode -ne 200) { throw ('ARM HTTP ' + $r.StatusCode + ' for ' + $path + ': ' + $r.Content) }
        return ($r.Content | ConvertFrom-Json)
    }
    # Graph uses a different audience from ARM; do not reuse an ARM token.
    $access = Get-AzAccessToken -ResourceUrl 'https://graph.microsoft.com/' -ErrorAction Stop
    $bearer = $null
    if ($access.Token -is [System.Security.SecureString]) {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($access.Token)
        try { $bearer = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } else { $bearer = [string]$access.Token }
    try { return (Invoke-RestMethod -Method GET -Uri $url -Headers @{Authorization=('Bearer ' + $bearer)} -ErrorAction Stop) }
    finally { $bearer = $null }
}
function Get-Machine([string]$n) {
    if ($script:fixture) { return (Field (Field $script:fixture 'machines') $n) }
    $u = $armRoot + $base + 'Microsoft.HybridCompute/machines/' + [uri]::EscapeDataString($n) + '?api-version=2024-07-10'
    return (Get-Http $u)
}
function Get-Extensions([string]$n) {
    if ($script:fixture) { return @(Field (Field $script:fixture 'extensions') $n) }
    $u = $armRoot + $base + 'Microsoft.HybridCompute/machines/' + [uri]::EscapeDataString($n) + '/extensions?api-version=2024-07-10'
    return @((Get-Http $u).value)
}
function Get-EntraDevices([string]$n) {
    if ($script:fixture) { return @(Field (Field $script:fixture 'entraDevices') $n) }
    $filter = [uri]::EscapeDataString("displayName eq '$n'")
    $u = 'https://graph.microsoft.com/v1.0/devices?$filter=' + $filter + '&$select=displayName,trustType,accountEnabled,deviceId'
    return @((Get-Http $u).value)
}
function Get-Hosts([string]$pool,[string]$key) {
    if ($script:fixture) { return @(Field (Field $script:fixture 'hosts') $key) }
    $u = $armRoot + $base + 'Microsoft.DesktopVirtualization/hostPools/' + [uri]::EscapeDataString($pool) + '/sessionHosts?api-version=2025-10-10'
    $items = New-Object 'System.Collections.Generic.List[object]'
    do {
        $page = Get-Http $u
        foreach ($item in @($page.value)) { if ($null -ne $item) { $items.Add($item) } }
        $u = Field $page 'nextLink'
        if (-not $u) { $u = Field $page '@odata.nextLink' }
    } while ($u)
    return @($items.ToArray())
}
function Is-ExtensionHealthy($ext) {
    if ((Field (Field $ext 'properties') 'provisioningState') -ne 'Succeeded') { return $false }
    $view = Field (Field $ext 'properties') 'instanceView'
    $status = Field $view 'status'
    $code = Field $status 'code'
    if ($null -ne $code -and [string]$code -notin @('0','ProvisioningState/succeeded')) { return $false }
    return $true
}
function Test-CurrentAzureContext {
    # Probe the exact resource type this script will read; a context's subscription
    # name alone does not prove its cached token is still valid.
    $probe = $armRoot + $base + 'Microsoft.HybridCompute/machines/' + [uri]::EscapeDataString($MachineNames[0]) + '?api-version=2024-07-10'
    try { $null = Get-Http $probe; return $true }
    catch {
        $reason = $_.Exception.Message
        if ($reason -match '401|ExpiredAuthenticationToken|Please run.*login|NoAccessToken') { return $false }
        throw ('Azure read failed (not an authentication prompt): ' + $reason)
    }
}
function Get-CliSubscription {
    $raw = & az account show --query id -o tsv --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return '' }
    return $raw.Trim()
}

if ($FixturePath) {
    $script:fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $script:authMode = 'Fixture (offline)'
} else {
    $hasCli = [bool](Get-Command az -ErrorAction SilentlyContinue)
    $hasPs = [bool](Get-Command Connect-AzAccount -ErrorAction SilentlyContinue)
    if ($Auth -eq 'AzureCLI' -and -not $hasCli) { Write-Error 'Azure CLI is not installed; install it or use -Auth AzPowerShell with Az.Accounts.'; exit 1 }
    if ($Auth -eq 'AzPowerShell' -and -not $hasPs) { Write-Error 'Az.Accounts is not installed; install it or use -Auth AzureCLI.'; exit 1 }
    if (-not $hasCli -and -not $hasPs) { Write-Error 'Neither Azure CLI nor Az.Accounts is installed. Install one on this machine, or run the script on an authenticated presenter machine.'; exit 1 }
    if ($Auth -eq 'AzPowerShell' -or ($Auth -eq 'Auto' -and -not $hasCli)) { $script:authMode='AzPowerShell' }
    else { $script:authMode='AzureCLI' }
    $valid = $false
    if ($script:authMode -eq 'AzureCLI') {
        if ((Get-CliSubscription) -ne $SubscriptionId) {
            # Already logged into another subscription? Switch without another MFA challenge.
            $null = & az account set --subscription $SubscriptionId --only-show-errors 2>&1 | Out-String
        }
        if ((Get-CliSubscription) -eq $SubscriptionId) { $valid = Test-CurrentAzureContext }
    } else {
        try {
            $ctx = Get-AzContext -ErrorAction SilentlyContinue
            if ($ctx -and $ctx.Subscription.Id -eq $SubscriptionId) { $valid = Test-CurrentAzureContext }
        } catch { throw }
    }
    if (-not $valid) {
        if ($NoLogin) { Write-Error 'No usable Azure sign-in for this subscription (-NoLogin was specified).'; exit 1 }
        if ($script:authMode -eq 'AzureCLI') {
            Write-Host 'Azure sign-in required. Complete the device-code prompt on your own device; do not paste a code into chat.'
            & az login --use-device-code --only-show-errors
            if ($LASTEXITCODE -ne 0) { Write-Error 'Azure CLI sign-in did not complete.'; exit 1 }
            $setOutput = & az account set --subscription $SubscriptionId --only-show-errors 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { Write-Error ('Signed in, but cannot select subscription ' + $SubscriptionId + ': ' + $setOutput.Trim()); exit 1 }
        } else {
            Write-Host 'Azure sign-in required. Complete the device-code prompt on your own device; do not paste a code into chat.'
            Connect-AzAccount -UseDeviceAuthentication -Subscription $SubscriptionId -ErrorAction Stop | Out-Host
        }
        if (-not (Test-CurrentAzureContext)) { Write-Error 'Sign-in returned, but an authenticated ARM read still failed. Check the chosen tenant and subscription.'; exit 1 }
    }
}
Write-Host ('MMS AVD Hybrid status | Phase: {0} | Subscription: {1} | Auth: {2}' -f $Phase,$SubscriptionId,$script:authMode)
if ($script:fixture) { Write-Warning 'OFFLINE TEST FIXTURE — NOT LIVE AZURE DATA; never use this mode for a demo readiness claim.' }
Write-Host 'PASS=healthy; READY=broker available; STAGED=intentionally unregistered; INFO=not required; WARN=investigate; FAIL/ERROR=stop.'
$poolHosts = @{}
foreach ($pair in @(@($LiveHostPool,'Live'),@($ReadyHostPool,'Ready'))) {
    try { $poolHosts[$pair[1]] = @(Get-Hosts $pair[0] $pair[1]) }
    catch { $poolHosts[$pair[1]] = $null; Add-Check 'POOL' ($pair[1]+' host pool') 'ERROR' $_.Exception.Message }
}
if ($Phase -eq 'Staged' -and $null -ne $poolHosts['Live'] -and @($poolHosts['Live']).Count -ne 0) {
    Add-Check 'POOL' 'Live pool staged empty' 'FAIL' ('contains {0} session host(s); inspect before presenting' -f @($poolHosts['Live']).Count)
}
foreach ($n in $MachineNames) {
    Write-Host ('--- ' + $n + ' ---')
    $machine = $null; $exts = @(); $arcId = $null
    try {
        $machine = Get-Machine $n
        if (-not $machine) { throw 'Arc machine not found' }
        $arcId = [string](Field $machine 'id')
        $arcProps = Field $machine 'properties'
        $arcStatus = [string](Field $arcProps 'status')
        $arcAgent = [string](Field $arcProps 'agentVersion')
        if ($arcStatus -eq 'Connected') { Add-Check $n 'Azure Arc' 'PASS' ('Connected; agent ' + $arcAgent) }
        else { Add-Check $n 'Azure Arc' 'FAIL' ('reported ' + $arcStatus) }
    } catch { Add-Check $n 'Azure Arc' 'ERROR' $_.Exception.Message }
    try {
        $exts = @(Get-Extensions $n)
        $avdExt = @($exts | Where-Object { (Field (Field $_ 'properties') 'type') -eq 'CloudDeviceExtension' -and (Field (Field $_ 'properties') 'publisher') -eq 'Microsoft.AzureVirtualDesktop' })
        $aadExt = @($exts | Where-Object { ((Field $_ 'name') -match 'AADLoginForWindows|AzureADLoginForWindows') -or ((Field (Field $_ 'properties') 'type') -match 'AADLoginForWindows') })
        if ($aadExt.Count -eq 0) { Add-Check $n 'Azure AD login extension' 'INFO' 'AADLoginForWindows not installed (not required); hybrid join is checked through Entra Graph' }
        elseif ($aadExt.Count -eq 1 -and (Is-ExtensionHealthy $aadExt[0])) { Add-Check $n 'Azure AD login extension' 'PASS' 'optional extension Succeeded' }
        else { Add-Check $n 'Azure AD login extension' 'WARN' 'optional extension present but not healthy; check its instance view' }
        $shouldStage = ($Phase -eq 'Staged' -and $n -ne $ExpectedReadyMachine)
        if ($avdExt.Count -eq 1 -and (Is-ExtensionHealthy $avdExt[0])) {
            if ($shouldStage) { Add-Check $n 'AVD Arc extension' 'FAIL' 'installed prematurely; staged machine should not have it yet' }
            else { Add-Check $n 'AVD Arc extension' 'PASS' 'Microsoft.AzureVirtualDesktop/CloudDeviceExtension Succeeded' }
        } elseif ($avdExt.Count -eq 0 -and $shouldStage) {
            Add-Check $n 'AVD Arc extension' 'STAGED' 'not installed yet, as planned for on-stage registration'
        } else { Add-Check $n 'AVD Arc extension' 'FAIL' ('missing, duplicated, or not Succeeded (found {0})' -f $avdExt.Count) }
    } catch { Add-Check $n 'Arc extensions' 'ERROR' $_.Exception.Message }
    try {
        $devices = @(Get-EntraDevices $n)
        $hybrid = @($devices | Where-Object { (Field $_ 'trustType') -eq 'ServerAd' -and (Field $_ 'accountEnabled') -eq $true })
        if ($devices.Count -eq 1 -and $hybrid.Count -eq 1) { Add-Check $n 'Entra hybrid join' 'PASS' 'Graph device enabled, trustType=ServerAd (not an Arc extension)' }
        else { Add-Check $n 'Entra hybrid join' 'FAIL' ('expected one enabled ServerAd device; found {0} total, {1} matching' -f $devices.Count,$hybrid.Count) }
    } catch { Add-Check $n 'Entra hybrid join' 'ERROR' $_.Exception.Message }
    if (-not $arcId) { Add-Check $n 'AVD registration' 'ERROR' 'Arc resource ID unavailable; cannot prove broker mapping'; continue }
    if ($null -eq $poolHosts['Live'] -or $null -eq $poolHosts['Ready']) {
        Add-Check $n 'AVD registration' 'ERROR' 'host pool query failed; cannot verify registration'; continue
    }
    $all = @($poolHosts['Live']) + @($poolHosts['Ready'])
    $found = @($all | Where-Object { [string]::Equals([string](Field (Field $_ 'properties') 'resourceId'),$arcId,[System.StringComparison]::OrdinalIgnoreCase) })
    $expectedPool = if ($n -eq $ExpectedReadyMachine) { $ReadyHostPool } else { $LiveHostPool }
    $shouldStage = ($Phase -eq 'Staged' -and $n -ne $ExpectedReadyMachine)
    if ($shouldStage -and $found.Count -eq 0) { Add-Check $n 'AVD registration' 'STAGED' 'not registered yet, as planned'; continue }
    if ($found.Count -ne 1) { Add-Check $n 'AVD registration' 'FAIL' ('expected one entry in {0}; found {1} broker mapping(s)' -f $expectedPool,$found.Count); continue }
    $sessionHost = $found[0];$hostName=[string](Field $sessionHost 'name');$hostProps=Field $sessionHost 'properties'
    if ($shouldStage -or -not $hostName.StartsWith($expectedPool+'/',[System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Check $n 'AVD registration' 'FAIL' ('registered in unexpected phase/pool: ' + $hostName);continue
    }
    $state=[string](Field $hostProps 'status');$sessions=Field $hostProps 'sessions'
    if ($state -eq 'Available') { Add-Check $n 'AVD registration' 'READY' ('{0}; Available; sessions={1}' -f $expectedPool,$sessions) }
    else { Add-Check $n 'AVD registration' 'FAIL' ('{0}; status={1}' -f $expectedPool,$state) }
    $heart = Field $hostProps 'lastHeartBeat'
    if (-not $heart) { Add-Check $n 'AVD heartbeat' 'WARN' 'no lastHeartBeat; Available is not a user-connection test' }
    else {
        try {
            # ConvertFrom-Json turns ISO-8601 Z timestamps into DateTime(UTC).
            # Casting that to string loses Z, and reparsing treats it as local time.
            if ($heart -is [DateTimeOffset]) { $stamp = $heart }
            elseif ($heart -is [DateTime]) {
                $utc = [DateTime]$heart
                if ($utc.Kind -eq [DateTimeKind]::Unspecified) { $utc = [DateTime]::SpecifyKind($utc,[DateTimeKind]::Utc) }
                $stamp = [DateTimeOffset]::new($utc)
            } else { $stamp = [DateTimeOffset]::Parse([string]$heart) }
            $age = ([DateTimeOffset]::UtcNow - $stamp).TotalMinutes
            if ($age -lt -1) { Add-Check $n 'AVD heartbeat' 'WARN' ('{0:N1} minutes in the future; check clock/timezone' -f (-$age)) }
            elseif ($age -ge 5) { Add-Check $n 'AVD heartbeat' 'WARN' ('{0:N1} minutes old; test an actual user connection' -f $age) }
            else { Add-Check $n 'AVD heartbeat' 'PASS' ('{0:N1} minutes old' -f $age) }
        } catch { Add-Check $n 'AVD heartbeat' 'WARN' ('could not parse ' + $heart) }
    }
    $joined = @((Field $hostProps 'sessionHostHealthCheckResults') | Where-Object { (Field $_ 'healthCheckName') -eq 'AADJoinedHealthCheck' })
    if ($joined.Count -eq 1 -and (Field $joined[0] 'healthCheckResult') -eq 'HealthCheckSucceeded') {
        Add-Check $n 'AVD guest Entra join check' 'PASS' 'AVD agent reports AADJoinedHealthCheck succeeded'
    } else { Add-Check $n 'AVD guest Entra join check' 'WARN' 'missing/failed guest check; Graph join is a different signal' }
}
$summary = [ordered]@{}
foreach ($s in @('PASS','READY','STAGED','INFO','WARN','FAIL','ERROR')) {
    $summary[$s.ToLowerInvariant()] = @($script:checks | Where-Object { $_.status -eq $s }).Count
}
Write-Host ('SUMMARY: PASS={0} READY={1} STAGED={2} INFO={3} WARN={4} FAIL={5} ERROR={6}' -f $summary.pass,$summary.ready,$summary.staged,$summary.info,$summary.warn,$summary.fail,$summary.error)
if (-not $JsonPath) { $JsonPath = Join-Path $PSScriptRoot 'MMS-AVDHybrid-Status.latest.json' }
$report = [pscustomobject]@{timeUtc=[DateTimeOffset]::UtcNow.ToString('o');phase=$Phase;subscriptionId=$SubscriptionId;resourceGroup=$ResourceGroup;summary=$summary;checks=@($script:checks.ToArray())}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
Write-Host ('JSON report: ' + $JsonPath)
if ($summary.fail -gt 0 -or $summary.error -gt 0) { exit 1 }
exit 0
