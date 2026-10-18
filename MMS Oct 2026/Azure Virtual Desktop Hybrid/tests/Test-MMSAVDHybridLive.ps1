#requires -Version 5.1
# Offline, dependency-free executable tests. Never loads Az or contacts Windows/Azure.
$ErrorActionPreference = 'Stop'
# Deny fall-through even if the tests are run on an authenticated Windows host.
# Individual test scopes replace these only with deterministic in-memory fakes.
function Invoke-AzRestMethod { throw 'OFFLINE GUARD: ARM access forbidden' }
function Connect-AzAccount { throw 'OFFLINE GUARD: authentication forbidden' }
function Get-CimInstance { throw 'OFFLINE GUARD: guest reads must be mocked' }
function Get-AzContext { throw 'OFFLINE GUARD: Azure context reads must be mocked' }
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Invoke-MMSAVDHybridLive.ps1'
$script:passed = 0
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Test($name, [scriptblock]$body) {
    & $body
    $script:passed++
    Write-Host "PASS $name"
}
function Reject([scriptblock]$body, $pattern) {
    $caught = $false
    try { & $body | Out-Null } catch { $caught = $true; Assert ($_.Exception.Message -match $pattern) "Wrong rejection: $($_.Exception.Message)" }
    Assert $caught "Expected rejection: $pattern"
}
Test 'production script exists' { Assert (Test-Path $source) 'Missing Live registration script' }
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'PowerShell parse failure'
# Load definitions only: the script entry point is NOT executed.
foreach ($node in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    . ([scriptblock]::Create($node.Extent.Text))
}
Test 'allowlist binds both Live hosts to UUID, refusing Ready and mismatches' {
    $one = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    Assert ($one.Vmid -eq 122) 'Wrong VMID 122'
    $two = Get-MmsTarget 'MMS-AVDHYB-02' '45DA37B2-1BE2-494D-9142-7B6FC78B564A'
    Assert ($two.Vmid -eq 123) 'Wrong VMID 123'
    Reject { Get-MmsTarget 'MMS-AVDHYB-03' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B' } 'allowlist'
    Reject { Get-MmsTarget 'MMS-AVDHYB-01' '45DA37B2-1BE2-494D-9142-7B6FC78B564A' } 'UUID'
    Reject { Get-MmsTarget 'MMS-AVDHYB-01' 'not-a-guid' } 'UUID'
}
function New-Evidence {
    $target = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    return [pscustomobject]@{
        Name=$target.Name; Uuid=$target.Uuid; Domain='AD.Mauvlan.Net'; PartOfDomain=$true
        SecureChannel=$true; JoinText="AzureAdJoined : YES`nDomainJoined : YES`nTenantId : $($target.Tenant)"
        Arc=[pscustomobject]@{status='Connected';resourceId=$target.ArcId;vmId='ed3b26c1-c41c-4361-9514-e48717eede55';vmUuid=$target.Uuid;tenantId=$target.Tenant}
        AvdPresent=$false
    }
}
Test 'local preflight requires exact Arc identity, hybrid join and clean registration' {
    $e = New-Evidence
    Assert ((Assert-MmsLocal $e).Name -eq $e.Name) 'Valid evidence rejected'
    foreach ($field in @('SecureChannel','PartOfDomain')) {
        $e = New-Evidence; $e.$field = $false
        Reject { Assert-MmsLocal $e } 'domain|channel'
    }
    $e = New-Evidence; $e.Domain='OTHER.NET'; Reject { Assert-MmsLocal $e } 'domain'
    $e = New-Evidence; $e.JoinText='DomainJoined : YES'; Reject { Assert-MmsLocal $e } 'hybrid'
    $e = New-Evidence; $e.Arc.status='Disconnected'; Reject { Assert-MmsLocal $e } 'Connected'
    $e = New-Evidence; $e.Arc.resourceId += '-03'; Reject { Assert-MmsLocal $e } 'Arc resource'
    $e = New-Evidence; $e.Arc.vmUuid='wrong'; Reject { Assert-MmsLocal $e } 'Arc VM UUID'
    $e = New-Evidence; $e.Arc.tenantId='wrong'; Reject { Assert-MmsLocal $e } 'tenant'
    $e = New-Evidence; $e.AvdPresent=$true; Reject { Assert-MmsLocal $e } 'already|present'
}
Test 'local Arc machine has a generated vmId distinct from SMBIOS vmUuid' {
    $e = New-Evidence
    $e.Arc.vmId = 'c0ab434e-63d7-446d-bad9-3b09b148073a'
    Assert ((Assert-MmsLocal $e).Vmid -eq 122) 'Matching SMBIOS vmUuid should pass despite distinct Arc vmId'
    $e.Arc.vmUuid = 'not-the-smbios-uuid'
    Reject { Assert-MmsLocal $e } 'UUID'
}
Test 'Check and WhatIf never authenticate or contact ARM' {
    function Get-MmsLocalEvidence { New-Evidence }
    function Open-MmsAzure { throw 'UNEXPECTED AUTH' }
    function Invoke-MmsArm { throw 'UNEXPECTED ARM' }
    Assert ((Invoke-MmsLive).State -eq 'LocallyStaged') 'Default must be local Check'
    $preview = Invoke-MmsLive -Action Register -WhatIf
    Assert ($preview.State -eq 'PlanOnly') 'WhatIf must return plan'
    Assert ($preview.LiveHostPool -notmatch 'Ready') 'Plan targets Ready'
}
Test 'local collector reads CIM, secure channel, dsregcmd and Arc without writes' {
    # Only base directories for the mocked native adapter; no Windows drives needed.
    $env:ProgramFiles = $PSScriptRoot; $env:SystemRoot = $PSScriptRoot
    function Get-CimInstance { param($ClassName)
        if ($ClassName -eq 'Win32_ComputerSystemProduct') { return @{UUID='81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'} }
        return @{Name='MMS-AVDHYB-01';Domain='AD.Mauvlan.Net';PartOfDomain=$true}
    }
    function Test-ComputerSecureChannel { $true }
    function Get-Service { @() }
    function Test-Path { $false }
    function Read-MmsNative { param($Path,$Arguments)
        if ($Path -match 'azcmagent') { return ((New-Evidence).Arc | ConvertTo-Json) }
        return (New-Evidence).JoinText
    }
    $e = Get-MmsLocalEvidence
    Assert ((Assert-MmsLocal $e).Vmid -eq 122) 'Collector did not bind guest to target'
    function Get-Service { @{Name='RDAgentBootLoader'} }
    Assert ((Get-MmsLocalEvidence).AvdPresent) 'Installed AVD service not detected'
    function Get-Service { @() }
    function Test-Path { $true }
    Assert ((Get-MmsLocalEvidence).AvdPresent) 'Installed AVD key/extension not detected'
}
Test 'WhatIf preview still reads the local secure channel instead of suppressing it' {
    $env:ProgramFiles = $PSScriptRoot; $env:SystemRoot = $PSScriptRoot
    function Get-CimInstance { param($ClassName)
        if ($ClassName -eq 'Win32_ComputerSystemProduct') { return @{UUID='81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'} }
        return @{Name='MMS-AVDHYB-01';Domain='AD.Mauvlan.Net';PartOfDomain=$true}
    }
    function Get-Service { @() }
    function Test-Path { $false }
    function Read-MmsNative { param($Path,$Arguments)
        if ($Path -match 'azcmagent') { return ((New-Evidence).Arc | ConvertTo-Json) }
        return (New-Evidence).JoinText
    }
    function Test-ComputerSecureChannel {
        [CmdletBinding(SupportsShouldProcess=$true)] param()
        if ($WhatIfPreference) { return $false }
        return $true
    }
    $WhatIfPreference=$true
    try {
        $e=Get-MmsLocalEvidence
        Assert ($e.SecureChannel -eq $true) 'Inherited WhatIf prevented secure-channel read'
    } finally { $WhatIfPreference=$false }
}
Test 'native read returns stdout and sanitizes failed command errors' {
    $exe = (Get-Process -Id $PID).Path
    Assert ((Read-MmsNative $exe @('-NoProfile','-Command','[Console]::WriteLine("native-read")')).Trim() -eq 'native-read') 'Native stdout lost'
    Reject { Read-MmsNative $exe @('-NoProfile','-Command','[Console]::Error.WriteLine("secret-must-not-escape"); exit 3') } '^Local read command failed\.$'
}
Test 'Azure context is process scoped and Status never initiates sign-in' {
    $t = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $script:loginCount=0; $script:autosave=$false; $script:loginContext=$null
    function Import-Module { param($Name) }
    function Disable-AzContextAutosave { param($Scope) Assert ($Scope -eq 'Process') 'Autosave scope'; $script:autosave=$true }
    function Get-AzContext { $script:loginContext }
    function Connect-AzAccount { param($Scope,$Tenant,$Subscription,[switch]$UseDeviceAuthentication)
        Assert ($Scope -eq 'Process' -and $UseDeviceAuthentication) 'Unsafe login'
        Assert ($Tenant -eq $t.Tenant -and $Subscription -eq $t.Subscription) 'Wrong login destination'
        $script:loginCount++
        $script:loginContext=@{Tenant=@{Id=$Tenant};Subscription=@{Id=$Subscription}}
        # The success object is not the authority. The selected process context is.
        return @{Context=@{Tenant=@{Id='wrong'};Subscription=@{Id='wrong'}}}
    }
    Reject { Open-MmsAzure $t } 'existing|context'
    Assert ($script:loginCount -eq 0) 'Status logged in'
    $ctx=Open-MmsAzure $t -Interactive
    Assert ($ctx.Subscription.Id -eq $t.Subscription -and $script:autosave -and $script:loginCount -eq 1) 'Process login missing'
}
Test 'ARM wrapper rejects errors without leaking secret response bodies' {
    function Invoke-AzRestMethod { param($Method,$Path,$Payload,$DefaultProfile)
        return @{StatusCode=403;Content='secret-must-not-escape'}
    }
    Reject { Invoke-MmsArm -Method GET -Path '/somewhere' -Context @{} } '^ARM GET failed \(HTTP 403\)\.$'
    function Invoke-AzRestMethod { throw 'secret-must-not-escape' }
    Reject { Invoke-MmsArm -Method PUT -Path '/somewhere' -Payload 'secret' -Context @{} } '^ARM PUT request failed; response suppressed for secret safety\.$'
    function Invoke-AzRestMethod { return @{StatusCode=200;Content='{"value":[]}'} }
    Assert ((Invoke-MmsArm -Method GET -Path '/somewhere' -Context @{}).StatusCode -eq 200) 'Wrapper lost success'
}
Test 'collection reader follows pages but rejects foreign or looping nextLink' {
    $script:calls=0
    function Invoke-MmsArm { param($Method,$Path,$Context)
        $script:calls++
        if ($script:calls -eq 1) { return @{Content='{"value":[{"name":"first"}],"nextLink":"https://management.azure.com/scope/list?api-version=x&skip=1"}'} }
        return @{Content='{"value":[{"name":"second"}]}'}
    }
    $items=@(Read-MmsCollection '/scope/list?api-version=x' @{})
    Assert ($items.Count -eq 2 -and $script:calls -eq 2) 'Pagination lost data'
    function Invoke-MmsArm { return @{Content='{"value":[],"nextLink":"https://evil.test/scope/list?api-version=x"}'} }
    Reject { Read-MmsCollection '/scope/list?api-version=x' @{} } 'nextLink'
    function Invoke-MmsArm { return @{Content='{"value":[],"nextLink":"/scope/list?api-version=x"}'} }
    Reject { Read-MmsCollection '/scope/list?api-version=x' @{} } 'loop'
}
function New-Cloud($t) {
    return [pscustomobject]@{Machine=@{id=$t.ArcId;location=$t.Location;properties=@{vmId='ed3b26c1-c41c-4361-9514-e48717eede55';detectedProperties=@{vmuuidEsu=$t.Uuid};status='Connected'}};Extensions=@();LiveHosts=@();ReadyHosts=@()}
}
Test 'ARM machine has a generated vmId distinct from detected SMBIOS vmuuidEsu' {
    $t = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $c = New-Cloud $t
    $c.Machine.properties.vmId = 'c0ab434e-63d7-446d-bad9-3b09b148073a'
    $c.Machine.properties.detectedProperties = @{vmuuidEsu=$t.Uuid}
    Assert-MmsCloud $t $c
    $c.Machine.properties.detectedProperties.vmuuidEsu = 'not-the-smbios-uuid'
    Reject { Assert-MmsCloud $t $c } 'UUID'
}
Test 'cloud inventory reads exact subscription, machine and both pools' {
    $t = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $script:paths=@()
    function Invoke-MmsArm { param($Method,$Path,$Context)
        Assert ($Method -eq 'GET') 'Inventory attempted a write'
        $script:paths += $Path
        if ($Path -match '^/subscriptions/[^/]+\?') { return @{Content=(@{tenantId=$t.Tenant;subscriptionId=$t.Subscription}|ConvertTo-Json)} }
        if ($Path -match '/machines/[^/]+\?') { return @{Content=((New-Cloud $t).Machine | ConvertTo-Json)} }
        return @{Content='{"value":[]}'}
    }
    $cloud=Read-MmsCloud $t @{}
    Assert ($script:paths.Count -eq 5) 'Missing scoped read'
    Assert (@($script:paths | Where-Object { $_ -eq ($t.ReadyId+'/sessionHosts?api-version=2025-10-10') }).Count -eq 1) 'Ready pool not checked'
    Assert-MmsCloud $t $cloud
    function Invoke-MmsArm { return @{Content='{"tenantId":"wrong"}'} }
    Reject { Read-MmsCloud $t @{} } 'tenant|subscription'
}
Test 'cloud guard refuses UUID drift, existing extension and duplicate host by every identity' {
    $t = Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $c=New-Cloud $t; $c.Machine.properties.detectedProperties.vmuuidEsu='wrong'; Reject { Assert-MmsCloud $t $c } 'UUID'
    $c=New-Cloud $t; $c.Machine.properties.status='Disconnected'; Reject { Assert-MmsCloud $t $c } 'Connected'
    $c=New-Cloud $t; $c.Machine.id += '-03'; Reject { Assert-MmsCloud $t $c } 'resource'
    $c=New-Cloud $t; $c.Extensions=@(@{name='Microsoft.AzureVirtualDesktop.CloudDeviceExtension';properties=@{}})
    Reject { Assert-MmsCloud $t $c } 'extension'
    $c=New-Cloud $t; $c.Extensions=@(@{name='renamed';properties=@{type='CloudDeviceExtension';publisher='Microsoft.AzureVirtualDesktop'}})
    Reject { Assert-MmsCloud $t $c } 'extension'
    foreach ($pool in @('LiveHosts','ReadyHosts')) {
        foreach ($hostRecord in @(@{name='pool/MMS-AVDHYB-01.AD.Mauvlan.Net';properties=@{}},
            @{name='pool/other';properties=@{resourceId=$t.ArcId}},
            @{name='pool/other';properties=@{virtualMachineId=$t.Uuid}})) {
            $c=New-Cloud $t; $c.$pool=@($hostRecord)
            Reject { Assert-MmsCloud $t $c } 'already|registered'
            Assert-MmsCloud $t $c -AllowRegistered
        }
    }
    $c=New-Cloud $t; $c.LiveHosts=@(@{name='pool/MMS-AVDHYB-02.AD.Mauvlan.Net';properties=@{}})
    Assert-MmsCloud $t $c # Host 01 may register after the independent host 02 starts.
}
Test 'Status emits only sanitized read-only cloud state after registration' {
    function Get-MmsLocalEvidence { $e=New-Evidence; $e.AvdPresent=$true; return $e }
    function Open-MmsAzure { param($Target,[switch]$Interactive) Assert (-not $Interactive) 'Status requested login'; return @{} }
    function Read-MmsCloud { param($Target,$Context)
        $c=New-Cloud $Target; $c.Extensions=@(@{name='Microsoft.AzureVirtualDesktop.CloudDeviceExtension';properties=@{type='CloudDeviceExtension';provisioningState='Creating';protectedSettings=@{registrationToken='secret-must-not-escape'}}})
        return $c
    }
    $result=Invoke-MmsLive -Action Status
    Assert ($result.State -eq 'AzureStatus') 'Status path missing'
    Assert (($result | ConvertTo-Json -Depth 10) -notmatch 'secret-must-not-escape') 'Status leaked secrets'
}
Test 'offline submission validates guards then uses only scoped PATCH POST PUT and one readback' {
    $t=Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $script:requests=@()
    function Get-MmsLocalEvidence { New-Evidence }
    function Read-MmsCloud { param($Target,$Context) New-Cloud $Target }
    function Invoke-MmsArm { param($Method,$Path,$Context,$Payload)
        $script:requests += @{Method=$Method;Path=$Path;Payload=$Payload}
        switch ($Method) {
            PATCH { return @{StatusCode=200;Content='{"properties":{"registrationInfo":{"token":"FAKE_OFFLINE_TOKEN"}}}'} }
            POST { return @{StatusCode=200;Content=(@{token='FAKE_OFFLINE_TOKEN';expirationTime=[DateTime]::UtcNow.AddHours(4).ToString('o')}|ConvertTo-Json)} }
            PUT { return @{StatusCode=202;Content='{}'} }
            GET { return @{StatusCode=200;Content=(@{id=($t.ArcId+'/extensions/Microsoft.AzureVirtualDesktop.CloudDeviceExtension');properties=@{provisioningState='Creating'}}|ConvertTo-Json)} }
        }
    }
    $result=Submit-MmsRegistration $t @{}
    Assert (($script:requests.Method -join ',') -eq 'PATCH,POST,PUT,GET') 'Unexpected request sequence or polling'
    Assert ($script:requests[0].Path -eq ($t.LiveId+'?api-version=2025-10-10')) 'Wrong PATCH target'
    $patch=$script:requests[0].Payload|ConvertFrom-Json
    Assert ($patch.properties.registrationInfo.registrationTokenOperation -eq 'Update') 'Wrong token action'
    $hours=([DateTimeOffset]::Parse($patch.properties.registrationInfo.expirationTime)-[DateTimeOffset]::UtcNow).TotalHours
    Assert ($hours -gt 3.98 -and $hours -le 4.01) 'Token must expire UTC+4h'
    Assert ($script:requests[1].Path -eq ($t.LiveId+'/retrieveRegistrationToken?api-version=2025-10-10')) 'Must POST retrieve token'
    $put=$script:requests[2].Payload|ConvertFrom-Json
    Assert ($script:requests[2].Path -eq ($t.ArcId+'/extensions/Microsoft.AzureVirtualDesktop.CloudDeviceExtension?api-version=2024-07-10')) 'Wrong extension target'
    Assert ($put.location -eq 'westus3' -and $put.properties.publisher -eq 'Microsoft.AzureVirtualDesktop' -and $put.properties.type -eq 'CloudDeviceExtension') 'Extension identity mismatch'
    Assert ($put.properties.typeHandlerVersion -eq '1.0' -and $put.properties.autoUpgradeMinorVersion -eq $true) 'Handler version / upgrade mismatch'
    Assert ($put.properties.settings.isCloudDevice -eq $false -and $put.properties.protectedSettings.registrationToken -eq 'FAKE_OFFLINE_TOKEN') 'Wrong settings/protected token'
    Assert (-not ($put.properties.settings.PSObject.Properties.Name -contains 'registrationToken')) 'Token put in public settings'
    Assert ($result.State -eq 'ExtensionAccepted' -and $result.ReadBack -eq 'Creating') 'Accepted must not claim registered'
    Assert (($result|ConvertTo-Json -Depth 10) -notmatch 'FAKE_OFFLINE_TOKEN') 'Result leaked token'
    Assert (@($script:requests | Where-Object { $_.Method -ne 'GET' -and $_.Path -match 'Ready' }).Count -eq 0) 'Write to Ready'
}
Test 'offline submission fails closed before writes and never PUTs a missing token' {
    $t=Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $script:writes=0
    function Get-MmsLocalEvidence { New-Evidence }
    function Read-MmsCloud { param($Target,$Context) $c=New-Cloud $Target; $c.ReadyHosts=@(@{name='pool/MMS-AVDHYB-01.ad.mauvlan.net';properties=@{}}); return $c }
    function Invoke-MmsArm { $script:writes++; throw 'Should not write' }
    Reject { Submit-MmsRegistration $t @{} } 'already registered'
    Assert ($script:writes -eq 0) 'Preflight made a write'
    function Read-MmsCloud { param($Target,$Context) New-Cloud $Target }
    function Invoke-MmsArm { param($Method)
        Assert ($Method -ne 'PUT') 'PUT must not happen'
        $script:writes++; return @{StatusCode=200;Content='{}'}
    }
    Reject { Submit-MmsRegistration $t @{} } 'token retrieval failed'
    Assert ($script:writes -eq 2) 'Expected PATCH then POST only'
}
Test 'script entrypoint is wired with safe default and explicit WhatIf propagation' {
    $text=[IO.File]::ReadAllText($source)
    Assert ($text -match "\[string\]\`$Action = 'Check'") 'Unsafe script default'
    Assert ($text -match 'Invoke-MmsLive -Action \$Action -WhatIf:\$WhatIfPreference') 'Missing real entrypoint'
    Assert ($text -notmatch '(?im)^\s*(Start-Transcript|Set-Content|Out-File|Export-Clixml|Save-AzContext)\b') 'Secret-persisting operation'
}
Test 'malformed extension inventory cannot establish safe absence' {
    $t=Get-MmsTarget 'MMS-AVDHYB-01' '81BCC02C-50E3-4ECF-8A86-D5180C42CC7B'
    $c=New-Cloud $t; $c.Extensions=@(@{properties=@{}})
    Reject { Assert-MmsCloud $t $c } 'Malformed.*extension'
}
Test 'copy-identical host 02 plan uses its own binding and readback failures remain unconfirmed' {
    function Get-MmsLocalEvidence {
        $e=New-Evidence
        $two=Get-MmsTarget 'MMS-AVDHYB-02' '45DA37B2-1BE2-494D-9142-7B6FC78B564A'
        $e.Name=$two.Name; $e.Uuid=$two.Uuid; $e.Arc.resourceId=$two.ArcId
        $e.Arc.vmId='c0ab434e-63d7-446d-bad9-3b09b148073a'; $e.Arc.vmUuid=$two.Uuid
        return $e
    }
    function Open-MmsAzure { throw 'Unexpected sign-in' }
    $plan=Invoke-MmsLive -Action Register -WhatIf
    Assert ($plan.Machine -eq 'MMS-AVDHYB-02' -and $plan.Vmid -eq 123) 'Host 02 plan binding mismatch'
    function Read-MmsCloud { param($Target,$Context) New-Cloud $Target }
    function Invoke-MmsArm { param($Method,$Path,$Context,$Payload)
        switch ($Method) {
            PATCH { return @{StatusCode=200;Content='{}'} }
            POST { return @{StatusCode=200;Content=(@{token='FAKE_OFFLINE_TOKEN';expirationTime=[DateTimeOffset]::UtcNow.AddHours(4).ToString('o')}|ConvertTo-Json)} }
            PUT { Assert ($Path -match '/machines/MMS-AVDHYB-02/extensions/') 'Wrong host 02 PUT'; return @{StatusCode=202} }
            GET { throw 'Unavailable readback (offline)' }
        }
    }
    $t=Assert-MmsLocal (Get-MmsLocalEvidence)
    $result=Submit-MmsRegistration $t @{}
    Assert ($result.ReadBack -like 'Unconfirmed*' -and $result.State -eq 'ExtensionAccepted') 'False success after failed readback'
}
Test 'operator help exposes runnable examples without executing the script' {
    $help=Get-Help -Name $source -Full
    Assert ($help.Synopsis -match '^Stages/checks') 'Comment-based operator help not discovered'
    Assert (@($help.Examples.Example).Count -eq 4) 'Missing operator examples'
}
Write-Host "RESULT: $script:passed tests passed (offline only)."
