# Windows 365 Cloud Apps — Demo Runbook

**Session:** Windows 365 Cloud Apps: An Easy Way to Publish Applications
**Presenters:** Adam Nichols, Chris Cavazos
**Format:** 90 minutes, five live demos
**Level:** 400

---

## Contents

1. [Before the session — environment prep](#before-the-session--environment-prep)
2. [Demo 1 — Build the Cloud Apps provisioning policy (13 min)](#demo-1--build-the-cloud-apps-provisioning-policy-13-min)
3. [Demo 2 — Publish, tune and rescue apps (14 min)](#demo-2--publish-tune-and-rescue-apps-14-min)
4. [Demo 3 — Hit the concurrency ceiling on purpose (12 min)](#demo-3--hit-the-concurrency-ceiling-on-purpose-12-min)
5. [Demo 4 — Script it end to end with Microsoft Graph (13 min)](#demo-4--script-it-end-to-end-with-microsoft-graph-13-min)
6. [Demo 5 — RemoteApp V2 side by side (10 min)](#demo-5--remoteapp-v2-side-by-side-10-min)
7. [Failure drills and recovery](#failure-drills-and-recovery)
8. [Reference — endpoints, fields and sources](#reference--endpoints-fields-and-sources)

---

## Before the session — environment prep

### Licensing and identity

| Item | Requirement | Notes |
|---|---|---|
| License | Windows 365 Flex (formerly Frontline) | Cloud Apps run on Flex Cloud PCs in **Shared mode**. No Flex, no Cloud Apps. |
| Groups | 2–3 Microsoft Entra ID security groups | One per demo policy, so concurrency limits are isolated per demo. |
| Roles | Intune Administrator (or equivalent) | For the portal demos. |
| App registration | Client ID + secret, admin consent | For Demo 4. Permissions: `CloudPC.ReadWrite.All`, `CloudPC.Read.All`, `DeviceManagementServiceConfig.ReadWrite.All`. |

> **Naming note for the room:** Windows 365 Frontline was renamed **Windows 365 Flex** in May 2026. The Intune admin center may still say *Frontline* in places — call this out early so nobody gets confused mid-demo.

### Pre-staged assets

| Asset | Purpose | Demo |
|---|---|---|
| Policy `CloudApps-Demo-Live` (gallery image, 2–3 licenses) | The policy you build live | 1 |
| Policy `CloudApps-Demo-Ready` (already provisioned, apps discovered) | Fallback so you never wait for provisioning on stage | 1, 2 |
| Policy `CloudApps-Demo-Capacity` (**1 license only**) | Guarantees you hit the ceiling on cue | 3 |
| Custom image with a legacy app that has **no Start-menu shortcut** | Proves the file-path escape hatch | 2 |
| Two Cloud PCs: one with `EnableRemoteAppV2=1`, one without | V2 comparison — needs a reboot, so never enable live | 5 |
| Second device (laptop/tablet) signed in as a second test user | Concurrency demo | 3 |
| Windows App **2.0.864.0 or newer** on the presenting device | Required for RemoteApp V2 | 5 |

### Stage hygiene

- Zoom It running (the template's own Attention slide promises it).
- Browser profiles pre-authenticated to the Intune admin center; MFA prompts pre-cleared.
- Terminal open at the script folder with the token already acquired once (so the first run is fast).
- Reset checklist ready: unpublish test apps, restore display names, remove file-path apps.

---

## Demo 1 — Build the Cloud Apps provisioning policy (13 min)

**Goal:** show that the entire Cloud Apps experience is one provisioning policy, and surface the two settings people miss.

### Steps

1. **Intune admin center → Devices → Windows 365 → Provisioning policies → Create policy.**
2. **General tab**
   - Name: `CloudApps-Demo-Live`
   - **Experience: `Access only apps`**
   - **Talking point:** this single choice defaults **License type** to Frontline/Flex and **Shared mode**. You do not pick those separately, and `provisioningType` cannot be changed after creation.
3. **Image tab**
   - Select a **gallery image**.
   - **Talking point:** the tab previews the apps you will be able to publish *before* a Cloud PC exists. APPX/MSIX apps do **not** appear in this preview even when they will later be discoverable.
4. **Configuration tab**
   - If you select an **Autopilot device preparation policy** (public preview), tick **"Prevent users from connecting to Cloud PC upon installation failure or timeout."**
   - **Talking point:** skipping that checkbox is the number-one reason Intune-delivered apps never show up as Cloud Apps — provisioning finishes before the apps install.
   - Enable **User Experience Sync (UES)** so app settings and Windows settings survive between sessions.
5. **Assignments tab** — assign the Entra group, choose the Flex service plan (size), and set the **allotment (license) count**.
6. **Review + create.**
7. Switch to **All Cloud PCs** — show provisioning starting. Switch to **All Cloud Apps** — show the row with status **Preparing**.
8. **Cut to the pre-staged `CloudApps-Demo-Ready` policy** where apps already show **Ready to publish**.

### What "good" looks like

- Cloud PCs with experience type **Cloud App** appear in All Cloud PCs.
- All Cloud Apps moves `Preparing` → `Ready to publish` once the first Cloud PC finishes.

### Talk track — how discovery actually works

Discovery is a **PowerShell script that scans the Start menu** of the provisioned Cloud PC. Consequences worth stating out loud:

- No Start-menu shortcut → the app is never discovered, no matter how correctly it is installed.
- Tenant security policy that forces **extra authentication for PowerShell** breaks discovery entirely.
- An **unsupported custom image** blocks discovery.
- **APPX/MSIX** support on an existing policy requires **reprovisioning** to pick them up.

---

## Demo 2 — Publish, tune and rescue apps (14 min)

**Goal:** walk the publish state machine, show that edits are instant, and prove the file-path escape hatch.

### Part A — Publish (3 min)

1. **All Cloud Apps** → select 2–3 apps with status **Ready to publish** → **Publish**.
2. Watch: `Ready to publish` → `Publishing` → `Published`.
3. Open **Windows App** on the presenting device — the apps appear for every user assigned to the policy.
4. Launch one and show it running as a seamless window on the local desktop.

### Part B — Edit and Reset (4 min)

1. Select a published app → **Edit**. Change:
   - **Display name** → something business-friendly (e.g. `Excel — Finance`)
   - **Description**
   - **Command line** (parameters)
   - **Icon path** and **Icon index**
2. Refresh Windows App — **the change is live within seconds**. Edits publish immediately; there is no second publish step.
3. **Reset** the app to roll every edit back to the discovered state.

> **Warning worth repeating:** **Unpublish also resets the app details.** Your display names and command lines are discarded, not parked. That is why the naming belongs in a source file (Demo 4).

### Part C — Add from file path (5 min)

Use this for the legacy app that discovery never found.

1. **All Cloud Apps → Add from file path.**
2. Fill in:

   | Field | Example |
   |---|---|
   | File path | `C:\Program Files\Contoso\LOB\contoso-lob.exe` |
   | App name | `ContosoLOB` |
   | Display name | `Contoso Orders` |
   | Description | `Order entry — production` |
   | Command-line parameters | `/env:PROD` |
   | Icon path | `C:\Program Files\Contoso\LOB\contoso-lob.exe` |
   | Icon index | `2` |

3. **Do it wrong first on purpose** — mistype the path, save, and show the **failed validation status**. The path is *validated, not created*: it must already exist on the Cloud PCs.
4. Correct the path, review and **publish**.

### Part D — Command line and icon patterns (2 min)

Three patterns worth demoing or describing:

- **One binary, many apps** — publish the same executable several times with different switches (`/env:PROD` vs `/env:TRAIN`), each with its own display name and icon.
- **A browser that is one app** — launch a browser in app mode pointed at a single line-of-business web app, so the user never sees an address bar or a second tab.
- **Icons are resources, not files** — `Icon path` + `Icon index` pulls a specific icon out of a binary carrying a dozen. Index `0` is rarely the good one.

---

## Demo 3 — Hit the concurrency ceiling on purpose (12 min)

**Goal:** make the licensing math visceral, then show the reports that stop it happening in production.

### Setup

Use `CloudApps-Demo-Capacity` — assigned with **exactly 1 license** (or 2 if you want a queue of one).

### Steps

1. State the rule before you demo it: **one Windows 365 Flex license = one concurrent session.** Many users can be assigned; only *N* can be connected, where *N* = licenses assigned **to that policy**.
2. **Device A** — sign in as User 1, launch the published app. Session established.
3. **Device B** — sign in as User 2, launch the same app. Show exactly what the blocked user sees. There is **no concurrency buffer in Shared mode** — user N+1 simply cannot connect.
4. **Device A** — **sign out properly** (not just close the window). All user data on that Cloud PC is deleted and the Cloud PC is released.
5. **Device B** — retry. Connection succeeds.
6. **Reports → Windows 365** — walk three things:
   - **Connected Windows 365 Flex Cloud PCs** report — who is on right now.
   - **Flex connection hourly report** — concurrency over time; this is what you size from.
   - **Flex concurrency alert** — configure it live so the ceiling pages you, not the service desk.

### Sizing method to say out loud

> Run the hourly report for at least a full business cycle. Size to the **95th percentile of concurrent sessions per policy**, not the absolute peak, and decide deliberately how much tail you leave uncovered. When you are short you have two levers: buy licenses for that policy, or **split the population into multiple policies each sized to its own shift peak** — usually cheaper, because shift peaks rarely coincide.

### The three gotchas

1. The **concurrency buffer is Dedicated mode only** — never Shared mode, never GPU-enabled Cloud PCs.
2. In a **mixed tenant**, newly added licenses feed **Dedicated mode policies first**, so a Cloud Apps policy can quietly stay under-provisioned.
3. **Closing the app window is not signing out.** An abandoned session holds a license until **idle timeout** fires — which makes idle timeout on the underlying Flex Cloud PC your cheapest license-reclaim lever.

---

## Demo 4 — Script it end to end with Microsoft Graph (13 min)

**Goal:** show that policy, capacity and app publishing are all code — and therefore reviewable, repeatable and diffable.

> All endpoints below are **Microsoft Graph beta**. Send `Prefer: include-unknown-enum-members`, pin your payloads, log the response body on failure, and re-test after service updates.

**Base path:** `https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/`

### Step 0 — Configuration and token

```powershell
# ---------- CONFIG ----------
$TenantId     = "<tenant-guid>"
$ClientId     = "<app-registration-client-id>"
$ClientSecret = "<client-secret>"

$DisplayName  = "CloudApps-Demo-Graph"
$Description  = "Windows 365 Cloud Apps - created from Graph"
$RegionName   = "eastus"          # or "automatic"
$Locale       = "en-US"
$ImageType    = "gallery"
$ImageId      = "microsoftwindowsdesktop_windows-ent-cpc_win11-24H2-ent-cpc-m365"

$GroupId              = "<entra-group-guid>"
$ServicePlanId        = "<flex-service-plan-guid>"   # enumerate, do not hard-code
$AllotmentCount       = 25                            # <-- your concurrency ceiling
$AllotmentDisplayName = "CP-FL-Shared-CloudApp"

# ---------- TOKEN (client credentials) ----------
$token = Invoke-RestMethod -Method Post `
  -Uri  "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
  -Body @{
      client_id     = $ClientId
      client_secret = $ClientSecret
      scope         = "https://graph.microsoft.com/.default"
      grant_type    = "client_credentials"
  } -ContentType 'application/x-www-form-urlencoded'

if (-not $token.access_token) {
    throw "No access_token. Confirm CloudPC.ReadWrite.All and DeviceManagementServiceConfig.ReadWrite.All are admin-consented."
}

$Headers = @{
    Authorization  = "Bearer $($token.access_token)"
    "Content-Type" = "application/json"
    Prefer         = "include-unknown-enum-members"   # survives beta enum drift
}

$Base       = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint"
$Policies   = "$Base/provisioningPolicies"
$CloudApps  = "$Base/cloudApps"
$CloudPCs   = "$Base/cloudPCs"
```

**Required application permissions (admin consent):**

- `CloudPC.ReadWrite.All` (and `CloudPC.Read.All`)
- `DeviceManagementServiceConfig.ReadWrite.All`

### Step 1 — Get-or-create the provisioning policy

The get-or-create pattern is what makes the script safe to re-run on stage.

```powershell
$escaped = $DisplayName.Replace("'","''")
$existing = Invoke-RestMethod -Method GET -Headers $Headers `
    -Uri "$Policies`?`$filter=displayName eq '$escaped'"

if ($existing.value.Count -gt 0) {
    $policy   = $existing.value[0]
    $policyId = $policy.id
    Write-Host "Reusing policy $policyId" -ForegroundColor Yellow
}
else {
    $body = @{
        "@odata.type"       = "#microsoft.graph.cloudPcProvisioningPolicy"
        displayName         = $DisplayName
        description         = $Description
        userExperienceType  = "cloudApp"              # <-- makes it a Cloud Apps policy
        provisioningType    = "sharedByEntraGroup"    # <-- Flex Shared mode
        imageType           = $ImageType
        imageId             = $ImageId
        enableSingleSignOn  = $true
        managedBy           = "windows365"
        microsoftManagedDesktop = @{
            "@odata.type" = "microsoft.graph.microsoftManagedDesktop"
            managedType   = "notManaged"
        }
        windowsSetting = @{
            "@odata.type" = "microsoft.graph.cloudPcWindowsSetting"
            locale        = $Locale
        }
        domainJoinConfigurations = @(
            @{
                "@odata.type"  = "microsoft.graph.cloudPcDomainJoinConfiguration"
                domainJoinType = "azureADJoin"
                type           = "azureADJoin"
                regionName     = $RegionName
            }
        )
    }

    $policy   = Invoke-RestMethod -Method POST -Headers $Headers -Uri $Policies `
                    -Body ($body | ConvertTo-Json -Depth 20)
    $policyId = $policy.id
    Write-Host "Created policy $policyId" -ForegroundColor Green
}
```

**The two properties that matter**

| Property | Value | Why |
|---|---|---|
| `userExperienceType` | `cloudApp` | Exactly what the portal writes when you pick **Access only apps**. Miss it and you get an ordinary Cloud PC policy. |
| `provisioningType` | `sharedByEntraGroup` | Flex Shared mode. **Cannot be changed after creation** — a mistake means delete and re-create. |

Gallery `imageId` format is `publisher_offer_sku`.

### Step 2 — Assign, with concurrency as a number in code

```powershell
$assignUri = "$Policies/$policyId/assign"

# Optional clean reset before reassigning
Invoke-RestMethod -Method POST -Headers $Headers -Uri $assignUri `
    -Body (@{ assignments = @() } | ConvertTo-Json -Depth 5) | Out-Null

$assignBody = @{
    assignments = @(
        @{
            target = @{
                "@odata.type"          = "#microsoft.graph.cloudPcManagementGroupAssignmentTarget"
                groupId                = $GroupId
                servicePlanId          = $ServicePlanId
                allotmentLicensesCount = $AllotmentCount        # <-- the ceiling
                allotmentDisplayName   = $AllotmentDisplayName
            }
        }
    )
}

Invoke-RestMethod -Method POST -Headers $Headers -Uri $assignUri `
    -Body ($assignBody | ConvertTo-Json -Depth 20) | Out-Null
```

### Step 3 — Verify (the 404 that is not a bug)

`/assignments` is **not addressable directly — it returns 404 by design.** Read the policy back with `$expand`, and retry, because assignments take a few seconds to materialise.

```powershell
$expandUri = "$Policies/$policyId`?`$expand=assignments"

for ($i = 1; $i -le 12; $i++) {
    $verify = Invoke-RestMethod -Method GET -Headers $Headers -Uri $expandUri
    if ($verify.assignments.Count -gt 0) { break }
    Start-Sleep -Seconds 3
}

$verify.assignments | ConvertTo-Json -Depth 10
```

Optionally poll for the Cloud PCs the policy produced:

```powershell
Invoke-RestMethod -Method GET -Headers $Headers `
    -Uri "$CloudPCs`?`$filter=provisioningPolicyId eq '$policyId'"
```

### Step 4 — List, publish and unpublish Cloud Apps

Publishing is a **batch** call — an entire catalogue is one request per direction.

```powershell
# List everything the service discovered
$apps = (Invoke-RestMethod -Method GET -Headers $Headers -Uri $CloudApps).value
$apps | Select-Object id, discoveredAppName, displayName, appStatus,
                      availableToUser, lastPublishedDateTime | Format-Table

# Filter by name
$excel = (Invoke-RestMethod -Method GET -Headers $Headers `
    -Uri "$CloudApps`?`$filter=displayName eq 'Microsoft Excel'").value

# Publish a batch
$ids = @($excel.id)
Invoke-RestMethod -Method POST -Headers $Headers -Uri "$CloudApps/publish" `
    -Body (@{ cloudAppIds = $ids } | ConvertTo-Json -Depth 5)

# Poll until published -- this is your pipeline gate
do {
    Start-Sleep -Seconds 5
    $state = (Invoke-RestMethod -Method GET -Headers $Headers -Uri "$CloudApps/$($ids[0])").appStatus
    Write-Host "appStatus = $state"
} while ($state -eq 'publishing')

# Unpublish
Invoke-RestMethod -Method POST -Headers $Headers -Uri "$CloudApps/unpublish" `
    -Body (@{ cloudAppIds = $ids } | ConvertTo-Json -Depth 5)
```

**Cloud App fields returned:** `id`, `discoveredAppName`, `displayName`, `appStatus`, `availableToUser`, `lastPublishedDateTime`.

### Step 5 — Desired state and drift detection

The same `GET` is your drift check: anything published that is not in your desired-state file should not be there.

```powershell
# desired-state.json  ->  [ "Microsoft Excel", "Microsoft Outlook", "Contoso Orders" ]
$desired = Get-Content .\desired-state.json | ConvertFrom-Json

$live      = (Invoke-RestMethod -Method GET -Headers $Headers -Uri $CloudApps).value
$published = $live | Where-Object { $_.appStatus -eq 'published' }

$toPublish   = $live      | Where-Object { $desired -contains $_.displayName -and $_.appStatus -ne 'published' }
$toUnpublish = $published | Where-Object { $desired -notcontains $_.displayName }

if ($toPublish)   { Invoke-RestMethod -Method POST -Headers $Headers -Uri "$CloudApps/publish"   -Body (@{ cloudAppIds = @($toPublish.id) }   | ConvertTo-Json -Depth 5) }
if ($toUnpublish) { Invoke-RestMethod -Method POST -Headers $Headers -Uri "$CloudApps/unpublish" -Body (@{ cloudAppIds = @($toUnpublish.id) } | ConvertTo-Json -Depth 5) }
```

> Because **unpublish resets edited details**, display names, descriptions, command lines and icon indexes must live in your source file — not only in the service.

### Optional — community module

The `PSCloudPC` PowerShell module wraps these same endpoints (`Get-CloudApp`, `Invoke-CPCPublishCloudApp`, `Invoke-CPCUnpublishCloudApp`, `New-CPCProvisioningPolicy`, `Set-CPCProvisioningPolicyAssignment`) if you would rather not hand-roll REST.

### Deliberate failure to show on stage

Send a bad enum value and surface the response body:

```powershell
try {
    $bad = $body.Clone(); $bad.userExperienceType = "cloudApplication"   # wrong on purpose
    Invoke-RestMethod -Method POST -Headers $Headers -Uri $Policies -Body ($bad | ConvertTo-Json -Depth 20)
}
catch {
    $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
    Write-Host $reader.ReadToEnd() -ForegroundColor DarkYellow
}
```

**Point:** on a beta surface, logging the response body is how you survive schema drift.

---

## Demo 5 — RemoteApp V2 side by side (10 min)

**Goal:** show the windowing improvements and how to ship them safely.

> **Pre-stage this.** Enabling V2 requires a **reboot** — never do it live.

### Prerequisites (both ends)

| Component | Minimum |
|---|---|
| Cloud PC — Windows 11 Enterprise 24H2 | build `26100.7309` (KB5070311) |
| Cloud PC — Windows 11 Enterprise 25H2 | build `26200.7309` (KB5070311) |
| SxS Network Stack | `1.0.2507.25750` or newer |
| Local device | Windows 11 24H2 or 25H2 |
| Windows App for Windows | `2.0.864.0` |
| Remote Desktop client for Windows | `1.2.6760.0` |

### Enablement

Set on the Cloud PC:

```
Key:        HKLM\Software\Policies\Microsoft\Windows NT\Terminal Services
Value name: EnableRemoteAppV2
Type:       REG_DWORD
Value:      1
```

Ship it with **Intune Remediations**, not baked into the image, so you can turn it off again.

**Detection script**

```powershell
$path = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
$v = (Get-ItemProperty -Path $path -Name EnableRemoteAppV2 -ErrorAction SilentlyContinue).EnableRemoteAppV2
if ($v -eq 1) { Write-Output "Compliant"; exit 0 } else { Write-Output "Not compliant"; exit 1 }
```

**Remediation script**

```powershell
$path = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
New-ItemProperty -Path $path -Name EnableRemoteAppV2 -PropertyType DWord -Value 1 -Force | Out-Null
Write-Output "EnableRemoteAppV2 set to 1 - reboot required"
exit 0
```

Also confirm these Group Policies are **not disabled** on the Cloud PC:

- Computer Configuration → Administrative Templates → Windows Components → Remote Desktop Services → Remote Desktop Session Host → Remote Session Environment → **Use advanced RemoteFX graphics for RemoteApp**
- …same path → **Enable enhanced shell experience for RemoteApp**

Then **reboot**.

### Steps

1. Launch the same published app from **both** Cloud PCs, side by side.
2. Compare: **Windows Snap**, **maximise / full screen**, **DPI handling on a secondary display**, and visuals — borders, shadows, theme integration.
3. **Prove which session type you are in:**
   - Windows App: press **Ctrl-Alt-End** → right-click the Windows Security dialog title bar → **Connection information** → **See details**.
   - Remote Desktop client: right-click the tray icon → hover the active connection → **Connection information**.
   - **"Remote session type" must read `RemoteAppV2`.** Anything else means a prerequisite is missing.
4. Show the Intune remediation that shipped the value.

### Known issues to set expectations

- Some enhancements are **not applied to Microsoft Edge and Chrome**.
- System notifications from RemoteApps sometimes render too low on screen.
- Narrowing a window already at minimum width can move it instead.
- The Snap flyout does not always honor display scale on secondary displays.
- Closing a RemoteApp window can change the foreground window.
- Parts of File Explorer as a RemoteApp can be unresponsive.

---

## Failure drills and recovery

Keep this open in a second window — it doubles as the audience's photograph-this slide.

| Symptom | Why it happens | First move |
|---|---|---|
| Cloud App stuck in **Preparing** | Provisioning completed but discovery never finished | Bulk reprovision the policy; if that fails, delete and re-create the policy assignment |
| App status **Failed** | Publish did not complete, or the shortcut/path is invalid | **Unpublish, then publish again**; validate the Start-menu shortcut on the image |
| Intune-delivered apps never appear | Autopilot device preparation finished before the apps installed | Select **Prevent users from connecting on install failure or timeout** |
| Nothing discovered on a custom image | PowerShell blocked by tenant policy, or unsupported image | Relax the extra PowerShell authentication requirement, or **publish from file path** |
| User cannot see a published app | Group assignment, or an outdated client | Confirm Entra group membership and update Windows App |
| Unexpected app launches (Edge opens from a link) | **By design** — a published app can launch anything installed on the Cloud PC | Not a bug. If it must not happen, use **Application Control for Windows** (audit first, enforce second) |
| User N+1 cannot connect | Concurrency ceiling reached; no buffer in Shared mode | Add licenses to that policy, or split users into multiple policies sized per shift peak |

**Reprovision is a genuine repair tool:** every app is rediscovered and republished, and file-path apps are re-validated and republished too.

---

## Reference — endpoints, fields and sources

### Graph beta endpoints used

| Operation | Method + path |
|---|---|
| List / create provisioning policies | `GET` / `POST` `/beta/deviceManagement/virtualEndpoint/provisioningPolicies` |
| Assign a policy | `POST` `/beta/.../provisioningPolicies/{policyId}/assign` |
| Verify assignments | `GET` `/beta/.../provisioningPolicies/{policyId}?$expand=assignments` |
| List Cloud PCs for a policy | `GET` `/beta/.../cloudPCs?$filter=provisioningPolicyId eq '{policyId}'` |
| List Cloud Apps | `GET` `/beta/.../cloudApps` |
| Get one Cloud App | `GET` `/beta/.../cloudApps/{id}` |
| Publish Cloud Apps | `POST` `/beta/.../cloudApps/publish` — body `{ "cloudAppIds": [ ... ] }` |
| Unpublish Cloud Apps | `POST` `/beta/.../cloudApps/unpublish` — body `{ "cloudAppIds": [ ... ] }` |

### Key payload fields

| Field | Where | Meaning |
|---|---|---|
| `userExperienceType` | provisioning policy | `cloudApp` = a Cloud Apps policy |
| `provisioningType` | provisioning policy | `sharedByEntraGroup` = Flex Shared mode; immutable after create |
| `imageType` / `imageId` | provisioning policy | `gallery` or `custom`; gallery IDs are `publisher_offer_sku` |
| `allotmentLicensesCount` | assignment target | **Concurrent sessions available to that policy** |
| `allotmentDisplayName` | assignment target | Friendly label shown with the assignment |
| `servicePlanId` | assignment target | The Flex size — enumerate rather than hard-code |
| `appStatus` | Cloud App | `readyToPublish` → `publishing` → `published` (and `failed`) |
| `availableToUser` | Cloud App | Whether users can see it in Windows App |
| `lastPublishedDateTime` | Cloud App | Useful for drift reports |

### Sources

- Microsoft Learn — *Windows 365 Cloud Apps* (prerequisites, create, publish/edit/reset/unpublish, add from file path, connect, troubleshooting)
- Microsoft Learn — *What is Windows 365 Flex?* (Dedicated vs Shared mode, concurrency, concurrency buffer, UES, unsupported features)
- Microsoft Learn — *RemoteApp enhancements (preview)* (build and client minimums, `EnableRemoteAppV2`, verification, known issues)
- Microsoft Learn — *cloudPcProvisioningPolicy resource type* (policy properties and assignment)
- AskAresh — *Windows 365 Cloud Apps* parts 1 and 2 (Graph REST policy creation, publishing, concurrency notes)
- `Windows365Management/PSCloudPC` (community module wrapping the `cloudApps` publish/unpublish endpoints)

> Timings in this runbook total 62 minutes of demo across five demos, leaving 28 minutes for content, transitions and Q&A within the 90-minute session.
