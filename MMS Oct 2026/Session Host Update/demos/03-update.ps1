#requires -Version 5.1

<#
.SYNOPSIS
  MMS Demo 3: check or run the one-host PowerShell session-host update.
.DESCRIPTION
  Check is read-only and requires an existing Az login. Run is explicitly gated
  by ShouldProcess, targets only hp-mms-cli in the MMS lab, and replaces its
  sole VM. Neither action starts parked VMs. -WhatIf is an offline preview:
  it exits before module import, authentication, or Azure reads.
.EXAMPLE
  ./03-update.ps1
.EXAMPLE
  ./03-update.ps1 -Action Run
.EXAMPLE
  ./03-update.ps1 -Action Run -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Check', 'Run')]
    [string]$Action = 'Check'
)

$ErrorActionPreference = 'Stop'
$SubscriptionId = 'e6ab1306-dfc4-4975-9f15-1df30c4699e2'
$TenantId = '280bf3c4-6674-481d-907a-2e873c775e72'
$ResourceGroupName = 'rg-MMS-SessionHostUpdate'
$HostPoolName = 'hp-mms-cli'
$HostName = 'hp-mms-cli/MMSCLI-0'
$TargetSize = 'Standard_D4as_v5'
$TargetDisk = 'Premium_LRS'

# An offline preview must not import modules, prompt for sign-in, or read Azure.
if ($WhatIfPreference) {
    Write-Output "PREVIEW ONLY: $Action on $HostPoolName in $ResourceGroupName/$SubscriptionId."
    Write-Output "No module import, Azure authentication, reads, or writes occurred."
    return
}

function Assert-MmsBaseline {
    param($Pool, $Configuration, $Management, [object[]]$Hosts, $Update, [string]$RequiredStatus)
    if ($null -eq $Pool -or $Pool.Name -ne 'hp-mms-cli' -or
        [string]$Pool.ManagementType -ne 'Automated' -or [string]$Pool.HostPoolType -ne 'Pooled') {
        throw 'Wrong host pool or management approach.'
    }
    if ($null -eq $Configuration -or [string]$Configuration.ProvisioningState -ne 'Succeeded' -or
        [string]$Configuration.VMSizeId -ne 'Standard_D2as_v5' -or
        [string]$Configuration.ManagedDiskType -ne 'StandardSSD_LRS' -or
        [string]$Configuration.CustomInfoResourceId -notmatch '/versions/1\.0\.0$') {
        throw 'Session-host configuration is not the D2as/Standard SSD/1.0.0 baseline.'
    }
    if ($null -eq $Management -or [int]$Management.ProvisioningInstanceCount -ne 1 -or
        [int]$Management.UpdateMaxVmsRemoved -ne 1 -or
        $Management.UpdateDeleteOriginalVM -ne $true) {
        throw 'Expected one host, batch size one, and delete-original enabled.'
    }
    if ($null -ne $Update) {
        throw 'An update status already exists on this pool. Inspect it before any new initiation.'
    }
    if ($null -eq $Hosts -or $Hosts.Count -ne 1 -or
        [string]$Hosts[0].Name -ne 'hp-mms-cli/MMSCLI-0' -or
        [string]$Hosts[0].ResourceId -notmatch '/resourceGroups/rg-MMS-SessionHostUpdate/providers/Microsoft\.Compute/virtualMachines/MMSCLI-0$') {
        throw 'Expected exactly the original MMSCLI-0 lab host.'
    }
    if ([int]$Hosts[0].ActiveSession -ne 0 -or [int]$Hosts[0].DisconnectedSession -ne 0) {
        throw 'A user session exists; do not run the replacement.'
    }
    if ($RequiredStatus -and [string]$Hosts[0].Status -ne $RequiredStatus) {
        throw "Host status is $($Hosts[0].Status), expected $RequiredStatus. Start the lab before this demo."
    }
}

try {
    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.DesktopVirtualization -ErrorAction Stop
    $command = Get-Command Update-AzWvdSessionHostConfiguration -ErrorAction Stop
    if ($command.Module.Version.ToString() -ne '6.0.1' -or
        [string]$command.Module.PrivateData.PSData.Prerelease -ne 'preview' -or
        -not $command.Parameters.ContainsKey('ManagedDiskType')) {
        throw 'Load Az.DesktopVirtualization 6.0.1-preview with -ManagedDiskType before the demo.'
    }

    if ($Action -eq 'Run') {
        Disable-AzContextAutosave -Scope Process | Out-Null
    }
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Subscription.Id -ne $SubscriptionId -or
        $context.Tenant.Id -ne $TenantId) {
        throw 'Sign in to the exact MMS subscription/tenant in this console before running.'
    }
    # Verify the tenant with ARM too; an Az cached-context label is not sufficient.
    $subscription = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId`?api-version=2022-12-01" `
        -Method GET -DefaultProfile $context -ErrorAction Stop
    if ($subscription.StatusCode -ne 200) { throw 'ARM subscription lookup failed.' }
    $authority = $subscription.Content | ConvertFrom-Json
    if ($authority.subscriptionId -ne $SubscriptionId -or $authority.tenantId -ne $TenantId) {
        throw 'ARM returned a different subscription or tenant.'
    }

    $parameters = @{
        ResourceGroupName = $ResourceGroupName
        HostPoolName = $HostPoolName
        SubscriptionId = $SubscriptionId
        ErrorAction = 'Stop'
    }
    $pool = Get-AzWvdHostPool -Name $HostPoolName -ResourceGroupName $ResourceGroupName `
        -SubscriptionId $SubscriptionId -ErrorAction Stop
    $configuration = Get-AzWvdSessionHostConfiguration @parameters
    $management = Get-AzWvdSessionHostManagement @parameters
    $hosts = @(Get-AzWvdSessionHost @parameters | Where-Object { $null -ne $_ })

    $statusPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/" +
                  "Microsoft.DesktopVirtualization/hostPools/$HostPoolName/sessionHostManagements/" +
                  "default/sessionHostUpdateStatuses/default?api-version=2025-04-01-preview"
    $response = Invoke-AzRestMethod -Path $statusPath -Method GET -DefaultProfile $context -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        $update = $response.Content | ConvertFrom-Json
    } elseif ($response.StatusCode -eq 404) {
        $update = $null
    } else {
        throw "Update-status lookup failed with HTTP $($response.StatusCode)."
    }
    Assert-MmsBaseline -Pool $pool -Configuration $configuration -Management $management `
        -Hosts $hosts -Update $update -RequiredStatus 'Available'
    Write-Output "READY: $HostName; image 1.0.0; $($configuration.VMSizeId); $($configuration.ManagedDiskType); batch 1."
    if ($Action -eq 'Check') { return }

    if (-not $PSCmdlet.ShouldProcess("$HostPoolName in $ResourceGroupName", `
            "Replace its one host with $TargetSize/$TargetDisk and schedule update now")) { return }

    # This configuration edit creates a new version; it does not itself schedule replacement.
    $null = Update-AzWvdSessionHostConfiguration @parameters -VMSizeId $TargetSize `
        -ManagedDiskType $TargetDisk
    $changed = $null
    for ($i = 0; $i -lt 6; $i++) {
        $changed = Get-AzWvdSessionHostConfiguration @parameters
        if ([string]$changed.ProvisioningState -eq 'Succeeded' -and
            [string]$changed.VMSizeId -eq $TargetSize -and
            [string]$changed.ManagedDiskType -eq $TargetDisk -and
            [string]$changed.Version -ne [string]$configuration.Version) { break }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $changed -or [string]$changed.ProvisioningState -ne 'Succeeded' -or
        [string]$changed.VMSizeId -ne $TargetSize -or
        [string]$changed.ManagedDiskType -ne $TargetDisk -or
        [string]$changed.Version -eq [string]$configuration.Version) {
        throw 'Configuration change was not verified. No update was scheduled.'
    }
    Write-Output "CONFIG VERIFIED: version $($changed.Version), size $($changed.VMSizeId), disk $($changed.ManagedDiskType)."
    Write-Output "POLICY: batch $($management.UpdateMaxVmsRemoved), delete original $($management.UpdateDeleteOriginalVM), logoff $($management.UpdateLogOffDelayMinute) minutes."

    # Exactly one initiation. Do not retry on a timeout or ambiguous response.
    $null = Invoke-AzWvdInitiateSessionHostUpdate @parameters
    $current = Get-AzWvdSessionHostManagementsUpdateStatus @parameters
    if ($null -eq $current -or [string]$current.Status -notin @(
            'Scheduled', 'ValidatingSessionHostUpdate', 'UpdatingSessionHosts')) {
        throw 'Initiation returned, but update state is unconfirmed. Read the exact pool before any retry.'
    }
    Write-Output "UPDATE VERIFIED: $($current.Status). Replacement continues asynchronously; do not run again."
} catch {
    $safeMessage = [string]$_.Exception.Message
    if ($safeMessage -match '^(Wrong host pool|Session-host configuration|Expected one host|An update status|Expected exactly|A user session|Host status is|Sign in to the exact|ARM returned|ARM subscription|Load Az\.DesktopVirtualization|Configuration change was not verified|Initiation returned|Update-status lookup failed)') {
        Write-Error "Demo 3 stopped safely at stage '$Action': $safeMessage"
    } else {
        Write-Error "Demo 3 stopped safely at stage '$Action' ($($_.Exception.GetType().Name)). Inspect the exact lab pool and do not blindly rerun."
    }
    exit 1
}
