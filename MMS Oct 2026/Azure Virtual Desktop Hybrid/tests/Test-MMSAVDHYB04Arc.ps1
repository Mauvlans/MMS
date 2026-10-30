#requires -Version 5.1
# Offline tests for the exact-host manual Arc onboarding script; no Azure calls.
$ErrorActionPreference = 'Stop'
function Invoke-AzRestMethod { throw 'OFFLINE GUARD: ARM forbidden' }
function Connect-AzAccount { throw 'OFFLINE GUARD: authentication forbidden' }
function Get-CimInstance { throw 'OFFLINE GUARD: guest reads must be mocked' }
function Start-Process { throw 'OFFLINE GUARD: installer execution forbidden' }
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Connect-MMSAVDHYB04Arc.ps1'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'MmsAvdHybrid.Config.ps1')
$script:MmsConfigPath = Join-Path $PSScriptRoot 'synthetic.config.json'
$script:passed = 0
function Assert($ok, [string]$message) { if (-not $ok) { throw $message } }
function Reject([scriptblock]$body, [string]$pattern) {
    $caught = $false
    try { & $body | Out-Null } catch { $caught = $true; Assert ($_.Exception.Message -match $pattern) ('Wrong rejection: ' + $_.Exception.Message) }
    Assert $caught ('Expected rejection: ' + $pattern)
}
function Test([string]$name, [scriptblock]$body) { & $body; $script:passed++; Write-Host ('PASS ' + $name) }
Test 'source exists and parses' { Assert (Test-Path -LiteralPath $source) 'Missing Connect-MMSAVDHYB04Arc.ps1' }
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'PowerShell parse errors'
foreach ($n in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($n.Extent.Text))
}
Test 'target binds only VMID 9004 by hostname and SMBIOS UUID' {
    $t = Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
    Assert ($t.Vmid -eq 9004 -and $t.Name -eq 'DEMO-AVD-04' -and $t.Location -eq 'westus3') 'Wrong target'
    Reject { Get-Arc04Target 'DEMO-AVD-03' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4' } 'hostname|allowlist'
    Reject { Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1' } 'UUID'
}
function New-Arc04Evidence {
    $t=Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
    return [pscustomobject]@{
        Name=$t.Name;Uuid=$t.Uuid;Domain='ad.example.test';Joined=$true;SecureChannel=$true
        AzureAdJoined='YES';DomainJoined='YES';TenantId=$t.Tenant
        Msi=[pscustomobject]@{Exists=$true;Size=117747712;Signature='Valid';Signer='CN=Microsoft Corporation';Sha256=$t.MsiSha256}
        Arc=$null
    }
}
Test 'local preflight accepts the signed staged installer and refuses foreign or invalid identities' {
    $t=Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
    $e=New-Arc04Evidence
    Assert ((Assert-Arc04Local $e $t).State -eq 'ReadyForManualConnection') 'Valid preflight rejected'
    $e=New-Arc04Evidence; $e.Msi.Signature='NotSigned'; Reject { Assert-Arc04Local $e $t } 'signature|installer'
    $e=New-Arc04Evidence; $e.Msi.Sha256='wrong'; Reject { Assert-Arc04Local $e $t } 'hash|installer'
    $e=New-Arc04Evidence; $e.SecureChannel=$false; Reject { Assert-Arc04Local $e $t } 'domain|channel'
    $e=New-Arc04Evidence; $e.AzureAdJoined='NO'; Reject { Assert-Arc04Local $e $t } 'hybrid|Entra'
    $e=New-Arc04Evidence; $e.Arc=[pscustomobject]@{Status='Connected';ResourceId=$t.ArcId;VmUuid=$t.Uuid;TenantId=$t.Tenant}
    Assert ((Assert-Arc04Local $e $t).State -eq 'AlreadyConnected') 'Known Arc connection not recognized'
    $e.Arc.ResourceId+='-OTHER'; Reject { Assert-Arc04Local $e $t } 'foreign|resource'
}
Test 'local collector reads exact guest/installer evidence even under inherited WhatIf' {
    $env:ProgramFiles=$PSScriptRoot; $env:SystemRoot=$PSScriptRoot
    function Get-CimInstance { param($ClassName)
        if($ClassName -eq 'Win32_ComputerSystemProduct'){return @{UUID='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'}}
        return @{Name='DEMO-AVD-04';Domain='ad.example.test';PartOfDomain=$true}
    }
    function Test-ComputerSecureChannel { [CmdletBinding(SupportsShouldProcess=$true)] param()
        if($ConfirmPreference -ne 'None'){throw 'LOCAL_CONFIRM_LEAK_SECURE_CHANNEL'}
        return (-not $WhatIfPreference)
    }
    function Read-Arc04Native { "AzureAdJoined : YES`nDomainJoined : YES`nTenantId : 22222222-2222-4222-8222-222222222222" }
    function Get-Service { $null }
    function Get-Item { @{Length=117747712} }
    function Get-AuthenticodeSignature { @{Status='Valid';SignerCertificate=@{Subject='CN=Microsoft Corporation'}} }
    function Get-FileHash { @{Hash='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'} }
    function Test-Path { param($LiteralPath);return ($LiteralPath -like '*AzureConnectedMachineAgent.msi') }
    $script:cimImported=$false
    function Import-Module { [CmdletBinding()] param([string]$Name)
        if($WhatIfPreference){throw 'CIM_IMPORT_SUPPRESSED'}
        if($ConfirmPreference -ne 'None'){throw 'LOCAL_CONFIRM_LEAK_MODULE'}
        Assert ($Name -eq 'CimCmdlets') 'Unexpected module import'
        $script:cimImported=$true
    }
    $priorConfirm=$ConfirmPreference;$ConfirmPreference='Low';$WhatIfPreference=$true
    try {
        $e=Get-Arc04LocalEvidence
        Assert ($e.SecureChannel -eq $true -and $e.Name -eq 'DEMO-AVD-04') 'Local evidence missing under WhatIf'
        Assert $script:cimImported 'CimCmdlets was not loaded without inherited WhatIf noise'
        Assert ($ConfirmPreference -eq 'Low') 'Local preflight changed caller confirmation policy'
        $t=Get-Arc04Target $e.Name $e.Uuid
        Assert ((Assert-Arc04Local $e $t).State -eq 'ReadyForManualConnection') 'Collector did not produce valid evidence'
    } finally {$WhatIfPreference=$false;$ConfirmPreference=$priorConfirm}
}
Test 'Check and Register WhatIf are distinct local-only outputs with no installer or login' {
    function Get-Arc04LocalEvidence { New-Arc04Evidence }
    function Install-Arc04Agent { throw 'UNEXPECTED_INSTALL' }
    function Connect-Arc04 { throw 'UNEXPECTED_CONNECT' }
    $check=Invoke-Arc04 -Action Check
    $preview=Invoke-Arc04 -Action Register -WhatIf
    Assert ($check.State -eq 'ReadyForManualConnection' -and $preview.State -eq 'PlanOnly') 'Check/preview states not distinct'
    Assert ($preview.ArcId -eq $check.ArcId -and $preview.Steps.Count -ge 2) 'Preview lacks exact target/actions'
    Assert ($check.Detail -ne $preview.Detail) 'Preview reused the Check description'
}
Test 'explicit Register verifies again after install before interactive Arc connection' {
    $script:steps=@();$script:reads=0
    function Get-Arc04LocalEvidence {
        $script:steps+='read';$script:reads++
        $e=New-Arc04Evidence
        if($script:reads -gt 1) {
            $e.Arc=[pscustomobject]@{Status='Disconnected';ResourceId='';VmUuid=$e.Uuid;TenantId=$e.TenantId}
        }
        return $e
    }
    function Test-Arc04Elevation { return $true }
    function Install-Arc04Agent { param($Target);$script:steps+='install' }
    function Connect-Arc04 { param($Target);$script:steps+='connect';return [pscustomobject]@{State='ConnectedLocal';Name=$Target.Name;ArcId=$Target.ArcId} }
    $result=Invoke-Arc04 -Action Register -Confirm:$false
    Assert ($result.State -eq 'ConnectedLocal') 'Register did not return the verified local result'
    Assert (($script:steps -join ',') -eq 'read,install,read,connect') ('Unexpected sequence: '+($script:steps -join ','))
}
Test 'Register refuses a non-elevated operator before invoking the Arc CLI' {
    function Get-Arc04LocalEvidence {
        $e=New-Arc04Evidence
        $e.Arc=[pscustomobject]@{Status='Disconnected';ResourceId='';VmUuid='';TenantId=''}
        return $e
    }
    function Test-Arc04Elevation { return $false }
    function Install-Arc04Agent { throw 'UNEXPECTED_INSTALL' }
    function Connect-Arc04 { throw 'UNEXPECTED_CONNECT' }
    Assert ((Invoke-Arc04 -Action Check).State -eq 'ReadyForManualConnection') 'Read-only Check should still work'
    Reject { Invoke-Arc04 -Action Register -Confirm:$false } 'elevated|Administrator'
}
Test 'installer execution uses the pinned Microsoft MSI silently without reboot and checks service' {
    $t=Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
    $script:msiArgs=$null
    function Get-FileHash { @{Hash='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'} }
    function Get-AuthenticodeSignature { @{Status='Valid';SignerCertificate=@{Subject='CN=Microsoft Corporation'}} }
    function Get-Item { @{Length=117747712} }
    function Start-Process { param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru)
        Assert ($FilePath -eq 'msiexec.exe' -and $Wait -and $PassThru) 'Wrong MSI launch'
        $script:msiArgs=$ArgumentList
        return @{ExitCode=0}
    }
    function Get-Service { @{Status='Running'} }
    function Test-Path { $true }
    Install-Arc04Agent $t
    $a=$script:msiArgs -join ' '
    Assert ($a -match '/i "C:\\Scripts\\AzureConnectedMachineAgent.msi"' -and $a -match '/qn' -and $a -match '/norestart' -and $a -match '/l\*v') 'Silent MSI arguments missing'
    $t.MsiPath='C:\Private Demo\AzureConnectedMachineAgent.msi'
    Install-Arc04Agent $t
    Assert ($script:msiArgs[1] -eq ('"'+$t.MsiPath+'"')) 'MSI path with spaces was not quoted'
    function Start-Process { return @{ExitCode=3010} }
    Reject { Install-Arc04Agent $t } 'reboot|required'
}
Test 'manual connect streams device-code auth to exact Arc target and verifies local identity' {
    $t=Get-Arc04Target 'DEMO-AVD-04' 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4'
    $env:ProgramFiles=$PSScriptRoot
    $script:connectArgs=@()
    function Test-Path { $true }
    function Invoke-Arc04ConnectNative { param($Exe,$Arguments);$script:connectArgs=@($Arguments);return 0 }
    function Read-Arc04Native { param($Path,$Arguments)
        return (@{resourceName=$t.Name;resourceId=$t.ArcId;subscriptionId=$t.Subscription;tenantId=$t.Tenant
            resourceGroup=$t.ResourceGroup;location=$t.Location;vmUuid=$t.Uuid;status='Connected'}|ConvertTo-Json)
    }
    $result=Connect-Arc04 $t
    Assert ($result.State -eq 'ConnectedLocal' -and $result.ArcId -eq $t.ArcId) 'Local readback missing'
    $a=$script:connectArgs -join ' '
    foreach($flag in @('--use-device-code','--resource-name DEMO-AVD-04','--subscription-id '+$t.Subscription,
        '--tenant-id '+$t.Tenant,'--resource-group '+$t.ResourceGroup,'--location westus3','--cloud AzureCloud')) {
        Assert ($a.Contains($flag)) ('Missing exact connect flag: '+$flag)
    }
    Assert ($a -notmatch 'access-token|service-principal-secret|registrationToken') 'Embedded credential in connect arguments'
    function Invoke-Arc04ConnectNative { return 44 }
    Reject { Connect-Arc04 $t } 'exit code 44'
}
Write-Host ('RESULT: ' + $script:passed + ' offline tests passed')
