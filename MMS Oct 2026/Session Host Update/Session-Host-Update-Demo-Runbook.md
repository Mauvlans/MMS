# Session Host Update — MMS Demo Runbook

Companion to the session **"Session Host Update: A Better Way to Manage Your AVD Environment"**
Presenters: Adam Nichols, Chris Cavazos · 5 demos · ~44 minutes of demo time inside a 90-minute slot

---

## 0. Lab build (do this before you travel)

The isolated lab is in subscription `e6ab1306-dfc4-4975-9f15-1df30c4699e2` (**MSFT - External Sub - Mauvlan**), resource group `rg-MMS-SessionHostUpdate`, region `westus3`. It has three independent live pooled host pools with session host configurations, plus a separate history/failure pool. Do not break a live demo pool to manufacture a failure. The lab hosts are **Microsoft Entra joined**, not AD DS joined; the AD-specific Q&A below describes the supported product behavior, not the lab's own join path.

Lab assets: gallery `galMMSSessionHostUpdate/Win11AVDTrusted` (versions `1.0.0` and `1.1.0`, two West US 3 replicas each), Key Vault `kvmmssessionhostupd`, Log Analytics workspace `law-MMS-SessionHostUpdate`, AVD workspace `ws-MMS-SessionHostUpdate`. VM prefixes are `MMSDEMO`, `MMSCHG`, `MMSCLI`, and `MMSHIST`. The existing `MVN-W3-VNET/AVDHosts` subnet is shared infrastructure; **do not modify its DNS, NSG, or address space for this demo**. All new VMs and their pools belong only to the named lab resource group.

| Pool | Purpose | Hosts | Notes |
|---|---|---|---|
| `hp-mms-demo` | Demos 1 and 4 (same running update) | 4 | D2as_v5, Standard SSD; batch size 2; do not schedule another update here before demo 4 |
| `hp-mms-change` | Demo 2 (portal image/size/disk change) | 1 | Starts on gallery image `1.0.0`, D2as_v5, Standard SSD; `1.1.0` is published and available; no spare capacity while this one host updates |
| `hp-mms-cli` | Demo 3 (PowerShell update) | 1 | Starts on D2as_v5 and Standard SSD, with no update already scheduled or running; use batch size 1 |
| `hp-mms-history` | Demo 5 and optional staged failure/retry | 1 | Dedicated lab pool; requires completed and failed update records within Log Analytics retention before demo 5 is live-ready |

**Applied footprint:** **4 + 1 + 1 + 1 = 7 session hosts**. Demo 1 has an initial host, a two-host batch, then a final host (roughly 60 minutes at the 20-minute-per-wave estimate); this does **not** guarantee an in-progress batch when Demo 4 arrives, so capture and verify a pause/resume recording as the primary path **before the event** (still an open readiness gate). A strict six-host footprint (3 + 1 + 1 + 1) would cut Demo 1 to roughly 40 minutes and make that live beat still less likely. The one-host `hp-mms-history` update was exercised successfully, proving a single-host pool can update its sole host, but has zero spare capacity during replacement. Keep separate portal-change, CLI, and history pools: only one update may run or be scheduled per pool.

The four excess lab hosts (`MMSDEMO-4`, `MMSDEMO-5`, `MMSCHG-1`, `MMSCLI-1`) were removed through AVD and their exact VM, 127-GiB Standard SSD OS disk, and NIC were read back absent (**508 GiB of provisioned OS disks removed**). The desired pool counts now match the seven registered hosts. All seven hosts and both generalized image-source VMs remain deallocated. This cuts persistent storage/quota, **not** running compute while parked. Never delete a VM record and assume its disk vanished; read back the exact VM, session-host object, desired instance count, disk, and NIC. The two image-source VMs are separate and were not touched.

**Required in the lab before the session**

- [x] All three live pools are **pooled/Automated** with a **Succeeded** session host configuration, and **7/7** desired session hosts remain registered after scale-in. The retained hosts had previously reached Available, but are now parked. Confirm the portal shows **Manage session host configuration** on the stage account; API state alone does not prove the blade renders.
- [ ] After the pre-session startup, read back all **7/7** hosts as **Available** with VMs running; this must be rechecked after scale-in, not inferred from the old 11-host rehearsal.
- [x] All lab session-host VMs are in **westus3** and `rg-MMS-SessionHostUpdate`.
- [x] **Azure Compute Gallery** versions `1.0.0` and `1.1.0` published with **two completed West US 3 replicas each**; their image-source VMs had different `C:\MMS-Demo\image-version.txt` markers. Verify the `1.1.0` marker on the replacement host after its update completes.
- [x] Gallery is in the **same subscription** as the host pools (cross-subscription gallery images are not supported).
- [x] Image is **generation 2 / TrustedLaunch**.
- [x] **Key Vault** holds the local-admin username/password as two separate secrets. The Entra-joined lab requires no AD domain-join credential; an AD-joined variant would require two more secrets plus a delegated join account. Each pool has a system-assigned managed identity and scoped Key Vault Secrets User access. Keep the temporary vault network/data-plane access tracked and restrict it after provisioning.
- [x] **Diagnostic settings** on every demo host pool send **Checkpoint**, **Error**, and **SessionHostManagement** to the lab Log Analytics workspace. Without the third category, the `WVDSessionHostManagement` table never appears.
- [x] No scaling plans exist in the subscription; keep all live-update pools free of one until updates finish. An enabled scaling plan during an update can fail it with a runtime error.
- [x] No resource locks found on the lab resource group; recheck before the event.
- [x] West US 3 DASv5 family: **28/65 vCPUs used** at the readiness probe, leaving **37** at that instant. Recheck immediately before simultaneous live updates. `Standard_D4as_v5` has a restriction in **zone 2** for this subscription; these lab VMs are non-zonal. Replacements are created before originals are deleted.
- [ ] On the **actual stage machine or Cloud Shell**, install a **preview** `Az.DesktopVirtualization` release with these cmdlets (a stable version number ≥5.3.0 is not sufficient). Run `Get-Command Update-AzWvdSessionHostConfiguration -Syntax` and confirm `-ManagedDiskType` against the loaded version. Rehearse demo 3 with that exact version.
- [ ] A test user has an active session on the host that will be selected first in `hp-mms-demo`; verify the notification appears in a rehearsal (selection is name-based, not guaranteed by merely signing in anywhere).
- [ ] Azure Cloud Shell, Log Analytics blade, and **all three** live host-pool blades open in pre-loaded browser tabs.
- [ ] **Zoom It** installed and tested — MMS audiences will ask for it.
- [ ] Screen recordings for **each stage-dependent beat**: sign-out notification, portal config change/version warning, PowerShell success, pause/resume, failed/retry state, and both Kusto result sets. Store offline on the presentation laptop and play every clip once without network access.
- [ ] Open the actual `hp-mms-history` workspace and run both queries below: Query A returns a completed update, Query B returns a real failure/error row within retention. If either is empty, use a verified recording instead of claiming live diagnostics.
- [ ] Run a full timed dress rehearsal in the exact demo order and record the subscription ID, pool IDs, module version, query row counts, clip paths, and the time each update reaches initial/batch/terminal status. **Do not mark ready until all five demos and their offline fallbacks pass.**

Run `python3 check_lab.py` from this folder on a machine signed in to the lab subscription with Azure CLI. It reads back the exact host count/status and VM power state in every pool, gallery replication, diagnostic settings, and **runs both embedded Kusto queries**. It exits nonzero on any missing result. A green script is only the *cloud-state* gate; the unchecked presentation/laptop/user-session items above remain mandatory. Do not run it against a different subscription by changing an ambient default.

**Power state between build/rehearsal and MMS:** all **7 session-host VMs** are deliberately **deallocated** to stop compute charges; the two generalized image-source VMs are also deallocated and must **never be started again**. Start the lab well before the session, not on stage:

```bash
python3 lab_power.py start      # scopes by exact pool IDs/VM ownership tags; never starts image-source VMs
python3 check_lab.py           # wait until all AVD hosts are Available, not merely VM PowerState/running
```

After the session, sign out users, then park and verify:

```bash
python3 lab_power.py deallocate  # refuses when any active/disconnected session remains
python3 lab_power.py status      # exits 0 only when all 7 session-host VMs are deallocated
```

Both scripts require Azure CLI signed into the named subscription. `check_lab.py` will intentionally fail while the lab is parked; **do not mark the session ready from a deallocated VM**. Verify the two `MMSIMG` source VMs remain deallocated separately; the power script deliberately excludes them.

**Timing reality check.** A session host takes roughly **20 minutes** to update. For four hosts at batch size two, budget about **60 minutes** (one initial ~20 minutes, then a two-host batch ~20 minutes, then one final host ~20 minutes); each one-host change/CLI pool is roughly **20 minutes**. These are estimates, not guarantees. After demos 1–3 (~26 minutes of demo time, plus slide time), demo 4 might find the update anywhere from the initial host to complete. Pause waits for in-flight work to complete; the portal's ~20-second status refresh is **not** the pause completion time. Use the recording as the *primary* way to show a completed pause/resume and end-to-end update, with the live lab as a bonus.

**Cost/blast-radius note.** Each *executed update* replaces VMs; a view-only walkthrough does not. Keep the pools small, and set `UpdateDeleteOriginalVM = $true` so the old VMs do not linger on the bill. Run only in session-owned lab pools, never an existing production or other-session pool.

**Temporary access and cleanup.** The new lab Key Vault currently has its public endpoint enabled for the AVD service to read local-admin secrets; its *direct vault-level* secret-reader assignments are scoped to the four pool identities (also review inherited tenant/subscription roles). The temporary human **Key Vault Secrets Officer** assignment used to stage those secrets was removed after provisioning. After the rehearsal, test a trusted-services/private-access configuration against a *dedicated* update before narrowing vault networking; do **not** disable the endpoint blindly while the demo updates still need the secrets. The image-source VMs `MMSIMG01` and `MMSIMG02` are generalized/deallocated but their disks and published gallery replicas still incur storage charges. Keep them until image provenance and fallback are confirmed, then remove **only these exact lab-owned resources** after the event; do not delete by name pattern or touch the shared `MVN-Networking` group. The lab vault secrets expire on 2026-11-30 and must be rotated if the lab is kept beyond that date.

---

## Demo 1 — Schedule an update from the Azure portal (~8 min, after slide "Demo 1")

**Point to make:** the whole thing is four blades and a schedule; the service handles drain, replace, rejoin.

1. Azure portal → search **Azure Virtual Desktop** → **Host pools** → `hp-mms-demo`.
2. Select **Session hosts**. Call out the **Current Version** and **Target Version** columns — this is the version stamp of the session host configuration each host is running.
3. Select **Manage session host configuration** → **View**. Walk the room through the actual lab configuration: gallery image `1.0.0`, VM size, disk type, Trusted Launch, **Microsoft Entra join**, local admin secret references, and the empty custom script field. Then select **Cancel** — viewing is safe; editing schedules an update.
4. Select **Manage session host update** → **New update**.
5. **Basics tab.** Point at **Current host pool size** (read-only), set **VM batch size authorized to be removed** to `2`, and read out **Session hosts available during the update** (read-only). Say the sentence out loud: *"batch size is the maximum number of hosts I am willing to lose at once."* Explain the **initial host**: one host updates alone first, and if it fails the update stops there.
6. **Session hosts tab.** Change nothing in this demo — say explicitly that if you change nothing, the hosts are redeployed with the same configuration (a legitimate "reset my pool to known-good" move).
7. **Schedule tab.** Choose **Schedule update now**. Mention the two-week scheduling horizon and the time zone selector.
8. **Notifications tab.** Set **Minutes before the users are signed out** to `5` (0–60 is the supported range) and type a real message, e.g. *"We're updating your desktop. Please save your work, sign out, and sign straight back in."*
9. **Review tab.** Wait for validation to pass, read the summary aloud, select **Update**.
10. Return to **Session hosts** and show the **blue status banner**. Select **Refresh** — point out it is a point-in-time view, and that progress only moves when a whole host completes (0.00% for the first ~20 minutes is expected, not broken).
11. Switch to the signed-in user's session and show the **sign-out notification** if it has arrived; otherwise play the pre-recorded notification clip. Do not wait on stage for name-based selection or the grace timer.

**Leave this update running.** You come back to it in demo 4.

**Talk track while it starts:** hosts are picked by name up to the batch size → users are notified → grace period → drain mode → removed from the pool → new VMs created as `SessionHostName-DateTime` → extensions rejoin **Microsoft Entra ID in this lab** and register the host → drain mode off → original VMs deleted.

**Failure mode on stage:** if validation fails, read the actual error (possible causes include a resource lock, missing Key Vault access, or an enabled scaling plan), then move to the recording; do not diagnose from the symptom alone.

---

## Demo 2 — Change image, VM size and disk type (~10 min, after slide "Demo 2")

**Point to make:** these are properties of the *configuration*, so a change is always pool-wide and always versioned.

1. On `hp-mms-change` → **Session hosts** → **Manage session host configuration** → **Edit**. Confirm no update is already scheduled or running on this pool.
2. **Image.** Select **See all images** → your Azure Compute Gallery → move from version `1.0.0` to `1.1.0`. Call out the rules while the picker is open:
   - Marketplace, Compute Gallery, or managed image.
   - Must be supported for AVD and match the VM generation.
   - At least two replicas recommended.
   - Same subscription as the host pool.
   - A gallery image with a **purchase plan** loses the plan on update — check first with `Get-AzGalleryImageVersion` or `az sig image-version show`.
3. **Virtual machine size.** Move up (or down) one size — e.g. `D2as_v5` → `D4as_v5`. Tie it to the right-sizing scenario from the deck.
4. **OS disk type.** Switch Standard SSD → **Premium SSD**. Two things to say: Premium is the production recommendation, and the **OS disk size cannot be changed here** — it follows the gallery image definition. The new disk is named `SessionHostName-DateTime_Hash`.
5. **Security type.** Open the dropdown and *narrate without changing it* (unless your image is gen 2 and you want the full demo): Trusted launch auto-selects secure boot and vTPM; Confidential VMs add integrity monitoring and you cannot opt out of vTPM.
6. **Directory.** Point to the lab's existing **Microsoft Entra** join selection and leave it unchanged. Explain that AD DS join instead needs a delegated domain-join account in Key Vault and can optionally target an OU, but **do not claim to show populated AD secret pickers in this Entra-joined lab**. You cannot switch directory type during an update.
7. **Custom configuration.** Show the script URL field but **leave it unchanged** unless a pre-tested, reachable, idempotent script URL is already staged. Never paste an unverified URL into a live update.
8. Continue through **Schedule** → **Notifications** → **Review** and select **Update**.
9. Back on **Session hosts**, show the new **timestamped target version** and warning icon on any host whose Current Version is behind Target Version. Do not promise every icon remains visible once replacement starts.

**Callout for the room:** everything a person hand-applied to a host — files, registry keys, certificates — is gone after this. Put it in the image, in Intune/GPO, or in the custom configuration script.

---

## Demo 3 — The same update in PowerShell (~8 min, after slide "Demo 3")

**Point to make:** everything in the portal is automatable, and this is how it goes in your pipeline.

Open Cloud Shell (PowerShell) or a local session with a **preview** `Az.DesktopVirtualization` build that exposes the commands below. This example was checked against `6.0.1-preview`; the stable `6.0.0` installed on the review machine **does not expose them**. On the stage machine, install/verify explicitly (installation is preparation, not an on-stage step):

```powershell
Install-Module Az.DesktopVirtualization -RequiredVersion '6.0.1-preview' -AllowPrerelease -Scope CurrentUser -Force
Import-Module Az.DesktopVirtualization
Get-Module Az.DesktopVirtualization | Select-Object Name, Version, @{Name='Prerelease';Expression={$_.PrivateData.PSData.Prerelease}}
Get-Command Update-AzWvdSessionHostConfiguration -Syntax
```

Stop if the loaded version is not `6.0.1-preview` or `-ManagedDiskType` is absent. Set/verify the intended subscription with `Get-AzContext` before any write. The values below name the *isolated* lab, not an existing production host pool.

```powershell
$rg   = 'rg-MMS-SessionHostUpdate'
$pool = 'hp-mms-cli'

# Preflight: refuse to write to an unintended subscription or pool.
$expectedSubscriptionId = 'e6ab1306-dfc4-4975-9f15-1df30c4699e2'
if ((Get-AzContext).Subscription.Id -ne $expectedSubscriptionId) { throw 'Wrong Azure subscription' }
$target = Get-AzWvdHostPool -ResourceGroupName $rg -Name $pool -ErrorAction Stop
if ($target.Name -ne $pool) { throw 'Wrong host pool' }

# 1. Read the current configuration
Get-AzWvdSessionHostConfiguration -ResourceGroupName $rg -HostPoolName $pool |
    Format-List Version, ImageInfo*, VMSizeId, ManagedDiskType, DomainInfo*

# 2. Change only what you need — every parameter you omit is left alone
Update-AzWvdSessionHostConfiguration `
    -ResourceGroupName $rg `
    -HostPoolName      $pool `
    -VMSizeId          'Standard_D4as_v5' `
    -ManagedDiskType   'Premium_LRS'

# 3. Confirm the change landed and a new version was stamped
Get-AzWvdSessionHostConfiguration -ResourceGroupName $rg -HostPoolName $pool |
    Format-List Version, VMSizeId, ManagedDiskType

# 4. Optional: set the defaults the update will run with
Update-AzWvdSessionHostManagement `
    -ResourceGroupName            $rg `
    -HostPoolName                 $pool `
    -UpdateMaxVmsRemoved          1 `
    -UpdateDeleteOriginalVM       $true `
    -UpdateLogOffDelayMinute      5 `
    -UpdateLogOffMessage          'Saving your work now - please sign out and sign back in.' `
    -ScheduledDateTimeZone        'Mountain Standard Time'

Get-AzWvdSessionHostManagement -ResourceGroupName $rg -HostPoolName $pool

# 5. Schedule the update (omit the scheduled time to start immediately)
Invoke-AzWvdInitiateSessionHostUpdate -ResourceGroupName $rg -HostPoolName $pool

# 6. Watch it
Get-AzWvdSessionHostManagementsUpdateStatus -ResourceGroupName $rg -HostPoolName $pool
```

**Say these things while the cmdlets run**

- These cmdlets are **preview**; pin and rehearse the same preview version used here. Stable `6.0.0` is not a substitute.
- `-UpdateDeleteOriginalVM $true` is the recommended setting — otherwise you own the cleanup of the old VMs.
- Time zone values come from `Get-TimeZone`, using the **StandardName** property.
- **Once an update is scheduled you cannot edit it.** To change anything, cancel it and schedule a new one.

**Tip:** `-DiskType` is not a parameter on `Update-AzWvdSessionHostConfiguration` in `6.0.1-preview`; the loaded cmdlet exposes `-ManagedDiskType`. If the stage module differs, stop and validate its actual syntax and return properties before presenting this sample.

---

## Demo 4 — Monitor, pause, resume, cancel (~10 min, after slide "Demo 4")

**Point to make:** you are never locked in mid-update, but cancel has a real cost.

1. Return to `hp-mms-demo` → **Session hosts**. Check whether the update from demo 1 is past the initial host; do not promise this by the demo-4 slot.
2. Show the **blue banner**, select **Refresh** and read the progress. Point at the host list: replaced hosts carry the `SessionHostName-DateTime` naming on their Azure resources while the **OS host name is unchanged**.
3. If an update is actively running and time permits, select **Manage session host update** → **Pause**. The banner may refresh after ~20 seconds, but the pause **does not complete until the batch in flight finishes**. Use the pre-recorded pause result if the batch is still running.
4. **Only after status reads Paused**, select **Resume** and show it continuing; otherwise play the recorded resume result. Mention: an update left paused for **two weeks is cancelled automatically**.
5. Show the **Cancel** and **Retry** buttons without pressing Cancel on the good pool. Give the warning verbatim: a cancelled update **cannot be resumed**, and a pool cancelled mid-flight can end up with **mixed OS versions or mixed domains** — schedule a replacement update immediately.
6. Switch to the separate `hp-mms-history` pool and show its **failed** update and **Retry** path only if that state was pre-staged and is safe to retry; otherwise use the recorded failure/retry clip. A *cancelled* update cannot be resumed. Note that a host pool with a failed update **cannot be deleted until the update is cancelled**.
7. Two rules to repeat: **do not remove VMs from the pool** and **do not touch drain mode** while an update is running — the service owns drain mode for the duration and resets it at the end.
8. Optional 30-second detour: **Azure Monitor → Activity log** filtered to the host pool, showing the same operations from the ARM side.

---

## Demo 5 — Prove it with Kusto (~8 min, after slide "Demo 5")

**Point to make:** "did it work, how long did it take, and what broke" are all queryable.

Open **Log Analytics** on the workspace attached to `hp-mms-history`. Have both queries **pre-pasted in tabs** — do not type Kusto on stage.

**Measured lab state:** the isolated `hp-mms-history` pool completed a real `1.0.0 → 1.1.0` update (the replacement host read back **Available**, **Microsoft Entra joined**, and its on-disk marker says `1.1.0`). Query A produced one real result after log ingestion. **Query B currently has zero rows**: no failed *update* has been staged, so this portion is **not live-ready**. Stage a failure safely in this dedicated pool and rerun the exact query, or capture a verified failure recording before claiming Demo 5 is ready. Do not present an unrelated configuration-validation failure as an update failure.

**Query A — successful updates, duration and median minutes per host (last 30 days)**

```kusto
let timeRange                            = ago(30d);
let succeededStatus                      = "Succeeded";
let hostPoolUpdateCompletedCheckpoint    = "HostPoolUpdateCompleted";
let sessionHostUpdateCompletedCheckpoint = "SessionHostUpdateCompleted";
let provisioningTypeUpdate               = "Update";
WVDSessionHostManagement
| where ProvisioningStatus == succeededStatus
    and TimeGenerated >= timeRange
    and ProvisioningType == provisioningTypeUpdate
| join kind = inner (
    WVDCheckpoints
    | where Name == hostPoolUpdateCompletedCheckpoint
    | extend ParametersParsed = parse_json(Parameters)
    | extend SessionHostUpdateCount = ParametersParsed["SessionHostsUpdateCompleted"],
             UpdateCompletionTime   = todatetime(ParametersParsed["TimeCompleted"]),
             UpdateStartTime        = todatetime(ParametersParsed["TimeStarted"])
    | project CorrelationId, SessionHostUpdateCount, UpdateStartTime, UpdateCompletionTime
) on CorrelationId
| join kind = inner (
    WVDCheckpoints
    | where Name == sessionHostUpdateCompletedCheckpoint
    | extend ParametersParsed = parse_json(Parameters)
    | extend SessionHostUpdateTime = todecimal(ParametersParsed["TimeTakenToUpdateSessionHostInSeconds"])
    | summarize SessionHostMedianUpdateTime = percentile(SessionHostUpdateTime, 50) by CorrelationId
) on CorrelationId
| project TimeGenerated, _ResourceId, CorrelationId,
          UpdateStartDateTime = UpdateStartTime,
          UpdateEndDateTime   = UpdateCompletionTime,
          ['UpdateDuration [InMinutes]'] = datetime_diff('minute', UpdateCompletionTime, UpdateStartTime),
          SessionHostUpdateCount,
          ['MedianSessionHostUpdateTime [InMinutes]'] = toint(SessionHostMedianUpdateTime / (60 * 1.0)),
          UpdateBatchSize = UpdateMaxVmsRemoved,
          FromSessionHostConfigVer, ToSessionHostConfigVer, UpdateDeleteOriginalVm
```

Land the point on **MedianSessionHostUpdateTime** and **UpdateBatchSize** together: that pair is how you size the next maintenance window instead of guessing.

**Query B — errors during updates (last 30 days)**

```kusto
let timeRange              = ago(30d);
let provisioningTypeUpdate = "Update";
WVDSessionHostManagement
| where ProvisioningStatus in ("Failed", "Error", "Canceled")
    and TimeGenerated >= timeRange
    and ProvisioningType == provisioningTypeUpdate
| summarize arg_max(TimeGenerated, _ResourceId, _SubscriptionId,
                    FromSessionHostConfigVer, ToSessionHostConfigVer) by CorrelationId
| join kind = inner (
    WVDErrors
    | where TimeGenerated >= timeRange
    | extend IsSessionHostResourceIdAvailable = iif(Message startswith "SessionHostResourceId", 1, 0)
    | extend startIndex = iif(IsSessionHostResourceIdAvailable == 1, indexof(Message, ":") + 1, 0)
    | extend length     = iif(IsSessionHostResourceIdAvailable == 1, indexof(Message, ";") - startIndex, 0)
    | extend SessionHostResourceId = iif(IsSessionHostResourceIdAvailable == 1, substring(Message, startIndex, length), "")
    | project TimeGenerated, CorrelationId, SessionHostResourceId, CodeSymbolic, Message
) on CorrelationId
| project TimeGenerated, _ResourceId, CorrelationId, CodeSymbolic,
          SessionHostResourceId, Message, FromSessionHostConfigVer, ToSessionHostConfigVer
```

Show a real `CodeSymbolic` from your lab **only if Query B returned a row**; otherwise play the verified failure recording. If you actually have `AgentRegistrationFailureGeneric`, it illustrates an intermittent large-batch failure that retrying often clears. Do not invent or promise that specific code.

**Close the demo block by naming the fix for the classic failure:** if the source image was captured from a running session host, delete `C:\packages\plugin` before capturing — that folder blocks the DSC extension that joins updated VMs to the host pool.

---

## Q&A ammunition (questions this room always asks)

| Question | Answer |
|---|---|
| Can I update one host? | You can't select one host *within a larger pool*; the update targets the pool. A one-host pool updates its sole host (proved in this lab), but has no remaining capacity during replacement. |
| Do I lose my AD computer objects? | **For AD DS-joined pools**, computer objects are reused, the OS host name is unchanged, and existing GPOs generally continue to apply; review OU changes and clean up orphaned objects if moving domains. **This lab is Entra joined and does not create AD computer objects.** |
| What about personal/dedicated pools? | Session host update targets **pooled** host pools with a session host configuration. |
| Does it work in Azure Government or 21Vianet? | No. Global Azure cloud only today. |
| Can I run updates on several pools at once? | Yes across pools; only one update running or scheduled **per pool** at a time. |
| Will AVD Insights keep working? | The Azure Monitor agent is not reinstalled automatically — deploy it with Azure Policy. |
| What if all my hosts are deallocated to save cost? | Supported — the existing power state and drain mode are honoured. |
| Can I change OS disk size? | Not in the update. It follows the gallery image definition. |
| How long will it take? | Roughly 20 minutes per host **wave**: one initial host, then concurrent batches. This lab's four-host demo pool at batch size two is roughly 60 minutes total; measure your own image and region. |

---

## Sources

- Microsoft Learn — [Session host update for Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/session-host-update)
- Microsoft Learn — [Update session hosts using session host update in Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/session-host-update-configure)
- Microsoft Learn — [Example diagnostic queries for session host update in Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/session-host-update-diagnostics)
- Microsoft Learn — [Troubleshoot session host update](https://learn.microsoft.com/en-us/azure/virtual-desktop/troubleshoot-session-host-update)
