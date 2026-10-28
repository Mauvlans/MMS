# Demo 3 — The same update in PowerShell (~8 min, after slide "Demo 3")

[← Session runbook](../Session-Host-Update-Demo-Runbook.md) · Presenter script

**Point to make:** everything in the portal is automatable, and this is how it goes in your pipeline.

**Stage preparation:** install `Az.DesktopVirtualization 6.0.1-preview` on the actual demo machine; stable `6.0.0` lacks the update cmdlets. Authenticate to the isolated lab and verify the loaded module **before** the session:

```powershell
Install-Module Az.DesktopVirtualization -RequiredVersion '6.0.1-preview' -AllowPrerelease -Scope CurrentUser -Force
Import-Module Az.DesktopVirtualization
$env:MMS_SUBSCRIPTION_ID = '<your-subscription-guid>' # from private deployment record
$env:MMS_TENANT_ID = '<your-tenant-guid>'               # never commit actual IDs
Connect-AzAccount -UseDeviceAuthentication -Tenant $env:MMS_TENANT_ID -Subscription $env:MMS_SUBSCRIPTION_ID
Get-AzContext | Select-Object Name, Tenant, Subscription
Get-Command Update-AzWvdSessionHostConfiguration -Syntax
```

Stop if the loaded version is not `6.0.1-preview` or `-ManagedDiskType` is absent. The stage script owns the executable example, so do not type its mutating lines on stage.

**Open:** [03-update.ps1](03-update.ps1). In PowerShell, run `./03-update.ps1` for the default read-only check. If it says `Shutdown`, start the **session-host lab** with `python3 lab_power.py start` from the parent `Session Host Update/` folder and rerun the common readiness check; never start the generalized image sources. Only when the pool is in its expected one-host baseline and you intend to start the real update, run `./03-update.ps1 -Action Run` and answer its confirmation. `-WhatIf` is an offline, no-login preview, **not** a cloud readiness check. The script does **not** wait for the roughly 20-minute replacement; watch the portal/status and use the rehearsal recording.

**Say these things while the cmdlets run**

- These cmdlets are **preview**; pin and rehearse the same preview version used here. Stable `6.0.0` is not a substitute.
- `-UpdateDeleteOriginalVM $true` is the recommended setting — otherwise you own the cleanup of the old VMs.
- Time zone values come from `Get-TimeZone`, using the **StandardName** property.
- **Once an update is scheduled you cannot edit it.** To change anything, cancel it and schedule a new one.

**Tip:** `-DiskType` is not a parameter on `Update-AzWvdSessionHostConfiguration` in `6.0.1-preview`; the loaded cmdlet exposes `-ManagedDiskType`. If the stage module differs, stop and validate its actual syntax and return properties before presenting this sample.
