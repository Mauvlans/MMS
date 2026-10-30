#requires -Version 5.1
# Dependency-free, offline config/authority regression tests. No cloud requests.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'MmsAvdHybrid.Config.ps1')
$script:MmsConfigPath=Join-Path $PSScriptRoot 'synthetic.config.json'
$fixturePath=$script:MmsConfigPath
$script:passed=0
function Assert($ok,$message) { if(-not $ok){throw $message} }
function Test($name,[scriptblock]$body) { & $body; $script:passed++; Write-Host ('PASS '+$name) }
function Reject([scriptblock]$body,$pattern) {
    $caught=$false
    try { & $body | Out-Null } catch { $caught=$true; Assert ($_.Exception.Message -match $pattern) ('Wrong rejection: '+$_.Exception.Message) }
    Assert $caught ('Expected rejection: '+$pattern)
}
function Connect-AzAccount { throw 'OFFLINE GUARD: authentication forbidden' }
function Invoke-AzRestMethod { throw 'OFFLINE GUARD: ARM forbidden' }
function Get-CimInstance { throw 'OFFLINE GUARD: Windows access forbidden' }
function Start-Process { throw 'OFFLINE GUARD: process writes forbidden' }

# All test output stays in the runtime-provided scratch directory, never in source.
$work=Join-Path ([IO.Path]::GetTempPath()) ('mms-config-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
try {
    Test 'synthetic complete config accepted with distinct Live Ready and Arc identities' {
        $c=Get-MmsDemoConfig
        Assert ($c.LiveHosts.Count -eq 2 -and $c.ReadyHost.Name -ne $c.ArcHost.Name) 'Fixture shape'
    }
    Test 'missing config and public blank template fail closed' {
        $script:MmsConfigPath=''
        Reject { Get-MmsDemoConfig } 'Required private config missing'
        $script:MmsConfigPath=Join-Path $root 'MmsAvdHybrid.config.example.json'
        Reject { Get-MmsDemoConfig } 'missing or invalid'
        $script:MmsConfigPath=$fixturePath
    }
    Test 'malformed and incomplete config rejected without accepting scalar-array coercion' {
        $script:MmsConfigPath=Join-Path $work 'invalid.private.json'
        '{bad json' | Set-Content -LiteralPath $script:MmsConfigPath
        Reject { Get-MmsDemoConfig } 'not readable JSON'
        foreach($change in @(
            {param($c) $c.SubscriptionId='not-a-guid'},
            {param($c) $c.TenantId='00000000-0000-0000-0000-000000000000'},
            {param($c) $c.TenantId=@($c.TenantId)},
            {param($c) $c.TenantId += "`n"},
            {param($c) $c.ArcHost.Uuid += "`n"},
            {param($c) $c.Domain=''},
            {param($c) $c.ResourceGroup='../foreign'},
            {param($c) $c.LiveHostPool=$c.ReadyHostPool},
            {param($c) $c.LiveHosts=@($c.LiveHosts[0])},
            {param($c) $c.ReadyHost.Name=$c.LiveHosts[0].Name},
            {param($c) $c.ArcHost.Uuid=$c.LiveHosts[0].Uuid},
            {param($c) $c.ReadyHost.Vmid=$c.LiveHosts[0].Vmid},
            {param($c) $c.LiveHosts[0].Vmid='9001'},
            {param($c) $c.MsiSha256=''},
            {param($c) $c.MsiSha256='0'*64},
            {param($c) $c.MsiPath='https://example.test/agent.msi'}
        )) {
            $c=Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
            & $change $c
            $c | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:MmsConfigPath
            Reject { Get-MmsDemoConfig } 'Private config'
        }
        $script:MmsConfigPath=$fixturePath
    }
    Test 'actual script entrypoints reject missing config before guest authentication or writes' {
        foreach($name in @('Invoke-MMSAVDHybridLive.ps1','Connect-MMSAVDHYB04Arc.ps1','Show-MMSAVDHybridStatus.ps1')) {
            Reject { & (Join-Path $root $name) -ConfigPath '' } 'Required private config missing'
            if ($name -ne 'Show-MMSAVDHybridStatus.ps1') {
                Reject { & (Join-Path $root $name) -ConfigPath '' -Action Register -Confirm:$false } 'Required private config missing'
                Reject { & (Join-Path $root $name) -ConfigPath '' -Action Register -WhatIf } 'Required private config missing'
            }
        }
        $script:MmsConfigPath=$fixturePath
    }
    Test 'a different private lab retargets every binding while preserving the exact-host allowlists' {
        foreach($file in @('Invoke-MMSAVDHybridLive.ps1','Connect-MMSAVDHYB04Arc.ps1')) {
            $tokens=$null; $errors=$null
            $tree=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors)
            Assert ($errors.Count -eq 0) 'Target source parse errors'
            foreach($n in $tree.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('Get-MmsTarget','Get-Arc04Target')},$false)) {
                . ([scriptblock]::Create($n.Extent.Text))
            }
        }
        $other=Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
        $other.SubscriptionId='33333333-3333-4333-8333-333333333333'
        $other.TenantId='44444444-4444-4444-8444-444444444444'
        $other.Domain='other.example.test'; $other.ResourceGroup='rg-other-demo'; $other.Location='eastus'
        $other.LiveHostPool='hp-other-live'; $other.ReadyHostPool='hp-other-ready'
        $other.MsiSha256='B'*64; $other.MsiPath='C:\Private Demo\agent.msi'
        $i=0
        foreach($h in (@($other.LiveHosts)+@($other.ReadyHost,$other.ArcHost))) {
            $i++; $h.Name='OTHER-AVD-0'+$i; $h.Vmid=9100+$i
            $h.Uuid='cccccccc-cccc-4ccc-8ccc-ccccccccccc'+$i
        }
        $script:MmsConfigPath=Join-Path $work 'other.private.json'
        try {
            $other | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:MmsConfigPath
            $t=Get-MmsTarget $other.LiveHosts[0].Name $other.LiveHosts[0].Uuid
            Assert ($t.Subscription -eq $other.SubscriptionId -and $t.Tenant -eq $other.TenantId -and $t.Domain -eq $other.Domain -and $t.Vmid -eq 9101 -and $t.Location -eq 'eastus') 'Live target ignored private bindings'
            Assert ($t.LiveId.EndsWith('/hostPools/hp-other-live') -and $t.ReadyId.EndsWith('/hostPools/hp-other-ready') -and $t.ArcId.Contains('/resourceGroups/rg-other-demo/')) 'Resource binding drift'
            Reject { Get-MmsTarget $other.ReadyHost.Name $other.ReadyHost.Uuid } 'allowlist'
            Reject { Get-MmsTarget $other.ArcHost.Name $other.ArcHost.Uuid } 'allowlist'
            Reject { Get-MmsTarget $other.LiveHosts[0].Name $other.LiveHosts[1].Uuid } 'UUID'
            $a=Get-Arc04Target $other.ArcHost.Name $other.ArcHost.Uuid
            Assert ($a.Vmid -eq 9104 -and $a.MsiPath -eq $other.MsiPath -and $a.MsiSha256 -eq $other.MsiSha256 -and $a.Tenant -eq $other.TenantId -and $a.Domain -eq $other.Domain) 'Arc target ignored private bindings'
            Reject { Get-Arc04Target $other.LiveHosts[0].Name $other.LiveHosts[0].Uuid } 'allowlist'
        } finally { $script:MmsConfigPath=$fixturePath }
    }
    $status=Join-Path $root 'Show-MMSAVDHybridStatus.ps1'
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($status,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Status parser errors'
    foreach($n in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
        . ([scriptblock]::Create($n.Extent.Text))
    }
    $c=Get-MmsDemoConfig
    $SubscriptionId=$c.SubscriptionId; $TenantId=$c.TenantId
    $armRoot='https://management.azure.com';$script:authMode='AzPowerShell'
    Test 'status context and ARM authority must both match configured tenant and subscription' {
        function Get-AzContext { @{Subscription=@{Id=$SubscriptionId};Tenant=@{Id=$TenantId}} }
        function Get-Http { param($url)
            Assert ($url -eq ($armRoot+'/subscriptions/'+$SubscriptionId+'?api-version=2022-12-01')) 'Wrong authority endpoint'
            @{subscriptionId=$SubscriptionId;tenantId=$TenantId}
        }
        Assert-StatusAuthority
        function Get-AzContext { @{Subscription=@{Id=$SubscriptionId};Tenant=@{Id='wrong'}} }
        Reject { Assert-StatusAuthority } 'context mismatch'
        function Get-AzContext { @{Subscription=@{Id='wrong'};Tenant=@{Id=$TenantId}} }
        Reject { Assert-StatusAuthority } 'context mismatch'
        function Get-AzContext { @{Subscription=@{Id=$SubscriptionId};Tenant=@{Id=$TenantId}} }
        function Get-Http { @{subscriptionId=$SubscriptionId;tenantId='wrong'} }
        Reject { Assert-StatusAuthority } 'authority mismatch'
        function Get-Http { @{subscriptionId='wrong';tenantId=$TenantId} }
        Reject { Assert-StatusAuthority } 'authority mismatch'
    }
    Test 'status CLI authority also rejects foreign tenant or subscription' {
        $script:authMode='AzureCLI'
        function az { $global:LASTEXITCODE=0; @{id=$SubscriptionId;tenantId=$TenantId}|ConvertTo-Json }
        function Get-Http { @{subscriptionId=$SubscriptionId;tenantId=$TenantId} }
        Assert-StatusAuthority
        function az { $global:LASTEXITCODE=0; @{id=$SubscriptionId;tenantId='wrong'}|ConvertTo-Json }
        Reject { Assert-StatusAuthority } 'context mismatch'
        function az { $global:LASTEXITCODE=0; @{id='wrong';tenantId=$TenantId}|ConvertTo-Json }
        Reject { Assert-StatusAuthority } 'context mismatch'
    }
    Test 'status full offline fixture executes with synthetic config and writes only scratch report' {
        $f=@{machines=@{};extensions=@{};entraDevices=@{};hosts=@{Live=@();Ready=@()}}
        $base='/subscriptions/'+$c.SubscriptionId+'/resourceGroups/'+$c.ResourceGroup+'/providers/'
        foreach($h in (@($c.LiveHosts)+@($c.ReadyHost))) {
            $id=$base+'Microsoft.HybridCompute/machines/'+$h.Name
            $f.machines[$h.Name]=@{id=$id;properties=@{status='Connected';agentVersion='synthetic'}}
            $f.extensions[$h.Name]=@()
            $f.entraDevices[$h.Name]=@(@{trustType='ServerAd';accountEnabled=$true})
            if($h.Name -eq $c.ReadyHost.Name) {
                $f.extensions[$h.Name]=@(@{name='avd';properties=@{type='CloudDeviceExtension';publisher='Microsoft.AzureVirtualDesktop';provisioningState='Succeeded'}})
                $f.hosts.Ready=@(@{name=$c.ReadyHostPool+'/'+$h.Name+'.'+$c.Domain;properties=@{resourceId=$id;status='Available';sessions=0;lastHeartBeat=[DateTime]::UtcNow.ToString('o');sessionHostHealthCheckResults=@(@{healthCheckName='AADJoinedHealthCheck';healthCheckResult='HealthCheckSucceeded'})}})
            }
        }
        $inventory=Join-Path $work 'inventory.json';$report=Join-Path $work 'report.json'
        $f | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $inventory
        $exe=(Get-Process -Id $PID).Path
        $output=& $exe -NoProfile -File $status -ConfigPath $fixturePath -FixturePath $inventory -JsonPath $report -NoColor 2>&1 | Out-String
        Assert ($LASTEXITCODE -eq 0) ('Status fixture failed: '+$output)
        Assert ($output -match 'OFFLINE TEST FIXTURE') 'Offline warning lost'
        $r=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        Assert ($r.summary.fail -eq 0 -and $r.summary.error -eq 0 -and $r.summary.ready -eq 1 -and $r.summary.staged -eq 4) 'Wrong offline readiness counts'
    }
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
Write-Host ('RESULT: '+$script:passed+' config/status offline tests passed')
