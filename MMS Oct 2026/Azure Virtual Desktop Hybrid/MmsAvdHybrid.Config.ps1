#requires -Version 5.1
# Local configuration only. No authentication, environment discovery or cloud calls.
function Get-MmsDemoConfig {
    if ([string]::IsNullOrWhiteSpace($script:MmsConfigPath) -or -not (Microsoft.PowerShell.Management\Test-Path -LiteralPath $script:MmsConfigPath -PathType Leaf)) {
        throw 'Required private config missing. Pass -ConfigPath to a reviewed private JSON file.'
    }
    try { $c = Get-Content -LiteralPath $script:MmsConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Private config is not readable JSON.' }
    if ($c -isnot [pscustomobject]) { throw 'Private config must be one JSON object.' }
    function Require-Text($Value, [string]$Pattern) {
        if ($Value -isnot [string] -or $Value -notmatch $Pattern) { throw 'Private config has a missing or invalid required field.' }
    }
    $guid = '^(?!00000000-0000-0000-0000-000000000000\z)[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\z'
    foreach ($v in @($c.SubscriptionId,$c.TenantId)) { Require-Text $v $guid }
    Require-Text $c.Domain '^(?=.{1,253}\z)[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+\z'
    foreach ($v in @($c.ResourceGroup,$c.LiveHostPool,$c.ReadyHostPool)) { Require-Text $v '^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,89}\z' }
    Require-Text $c.Location '^[a-z0-9]+\z'
    if ($c.LiveHostPool -eq $c.ReadyHostPool) { throw 'Private config Live and Ready pools must differ.' }
    if ($c.LiveHosts -isnot [array] -or $c.LiveHosts.Count -ne 2) { throw 'Private config requires exactly two Live hosts.' }
    $hosts = @($c.LiveHosts) + @($c.ReadyHost,$c.ArcHost)
    $names=@{}; $uuids=@{}; $vmids=@{}
    foreach ($h in $hosts) {
        Require-Text $h.Name '^(?=.{1,15}\z)[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*\z'
        Require-Text $h.Uuid $guid
        if ($h.Vmid -isnot [int] -and $h.Vmid -isnot [long]) { throw 'Private config VMIDs must be positive integers.' }
        if ($h.Vmid -le 0 -or $names.ContainsKey($h.Name) -or $uuids.ContainsKey($h.Uuid) -or $vmids.ContainsKey([string]$h.Vmid)) {
            throw 'Private config host names, UUIDs and VMIDs must be unique; Ready/Arc cannot be Live.'
        }
        $names[$h.Name]=$true; $uuids[$h.Uuid]=$true; $vmids[[string]$h.Vmid]=$true
    }
    Require-Text $c.MsiPath '^[a-zA-Z]:\\[^\r\n"]+\.msi\z'
    Require-Text $c.MsiSha256 '^(?!0{64}\z)[0-9a-fA-F]{64}\z'
    return $c
}
