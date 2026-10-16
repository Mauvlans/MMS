# Session Host Update — MMS Demo Runbook

Companion to the session **"Session Host Update: A Better Way to Manage Your AVD Environment"**
Presenters: Adam Nichols, Chris Cavazos · 5 demos · ~44 minutes of demo time inside a 90-minute slot

---

## 0. Lab build (do this before you travel)

Everything below assumes one lab subscription with **two pooled host pools**, both created **with a session host configuration**:

| Pool | Purpose | Hosts | Notes |
|---|---|---|---|
| `hp-mms-demo` | Live demos 1, 2, 4 | 6 | Small VM size (e.g. D2as_v5), Standard SSD, so updates are fast and cheap |
| `hp-mms-scratch` | Demo 3 (PowerShell) and failure demo | 3 | Safe to break; used for the "what happens when it fails" story |
| `hp-mms-history` | Demo 5 (diagnostics) | n/a | Any pool that already has several completed and one *failed* update in its Log Analytics history |

**Required in the lab before the session**

- [ ] Both pools are **pooled** and show **Manage session host configuration** on the Session hosts blade. A pool without a session host configuration cannot use session host update.
- [ ] All session hosts of a pool are in the **same Azure region and resource group**.
- [ ] **Azure Compute Gallery** with at least **two image versions** published (e.g. `1.0.0` and `1.1.0`) and **two replicas** each — the version swap is the heart of demo 2.
- [ ] Gallery lives in the **same subscription** as the host pool (cross-subscription gallery images are not supported).
- [ ] Image is **generation 2** if you plan to demo Trusted launch.
- [ ] **Key Vault** holding four secrets: domain-join username/password and local-admin username/password. If the vault uses private network access, attach a **managed identity** to the host pool; otherwise the vault must allow public access from all networks.
- [ ] **Diagnostic settings** on every demo host pool sending to a Log Analytics workspace, with at least the categories **Checkpoint**, **Error**, and **Session Host Management Activity Logs** enabled. Without the third category, the `WVDSessionHostManagement` table never appears.
- [ ] **Scaling plan disabled** on `hp-mms-demo` and `hp-mms-scratch`. An enabled scaling plan during an update can fail it with a runtime error.
- [ ] **Resource locks removed** from the hosts and their resource group.
- [ ] **vCPU quota** headroom for one full batch of extra VMs — new hosts are created before the old ones are deleted.
- [ ] `Az.DesktopVirtualization` **5.3.0 or later** (preview) installed on the demo machine, or Cloud Shell ready. Session host configuration cmdlets are in preview.
- [ ] A **user account with an active session** on one host in `hp-mms-demo` so the sign-out notification is real, not described.
- [ ] Azure Cloud Shell, Log Analytics blade, and the two host-pool blades open in **pre-loaded browser tabs**.
- [ ] **Zoom It** installed and tested — MMS audiences will ask for it.
- [ ] Screen recordings of a complete update (start → initial host → batch → complete) as a **fallback if the lab or venue Wi-Fi fails**.

**Timing reality check.** A session host takes roughly **20 minutes** to update. Nothing you start on stage finishes on stage. Start the demo-1 update early and come back to it in demo 4 — that is the whole reason demo 4 sits later in the deck.

**Cost/blast-radius note.** Every demo destroys and recreates VMs. Keep the pools small, and set `UpdateDeleteOriginalVM = $true` so the old VMs do not linger on the bill.

---

## Demo 1 — Schedule an update from the Azure portal (~8 min, after slide "Demo 1")

**Point to make:** the whole thing is four blades and a schedule; the service handles drain, replace, rejoin.

1. Azure portal → search **Azure Virtual Desktop** → **Host pools** → `hp-mms-demo`.
2. Select **Session hosts**. Call out the **Current Version** and **Target Version** columns — this is the version stamp of the session host configuration each host is running.
3. Select **Manage session host configuration** → **View**. Walk the room through the configuration: image, VM size, OS disk type, security type, domain to join, local admin, custom configuration script. Then select **Cancel** — stress that *viewing* is safe, *editing* schedules an update.
4. Select **Manage session host update** → **New update**.
5. **Basics tab.** Point at **Current host pool size** (read-only), set **VM batch size authorized to be removed** to `2`, and read out **Session hosts available during the update** (read-only). Say the sentence out loud: *"batch size is the maximum number of hosts I am willing to lose at once."* Explain the **initial host**: one host updates alone first, and if it fails the update stops there.
6. **Session hosts tab.** Change nothing in this demo — say explicitly that if you change nothing, the hosts are redeployed with the same configuration (a legitimate "reset my pool to known-good" move).
7. **Schedule tab.** Choose **Schedule update now**. Mention the two-week scheduling horizon and the time zone selector.
8. **Notifications tab.** Set **Minutes before the users are signed out** to `5` (0–60 is the supported range) and type a real message, e.g. *"We're updating your desktop. Please save your work, sign out, and sign straight back in."*
9. **Review tab.** Wait for validation to pass, read the summary aloud, select **Update**.
10. Return to **Session hosts** and show the **blue status banner**. Select **Refresh** — point out it is a point-in-time view, and that progress only moves when a whole host completes (0.00% for the first ~20 minutes is expected, not broken).
11. Switch to the signed-in user's session and show the **sign-out notification** they actually received.

**Leave this update running.** You come back to it in demo 4.

**Talk track while it starts:** hosts are picked by name up to the batch size → users are notified → grace period → drain mode → removed from the pool → new VMs created as `SessionHostName-DateTime` → extensions rejoin the directory and register the host → drain mode off → original VMs deleted.

**Failure mode on stage:** if validation fails, it is almost always a resource lock, a missing Key Vault secret, or a scaling plan still enabled. Say so and move to the recording.

---

## Demo 2 — Change image, VM size and disk type (~10 min, after slide "Demo 2")

**Point to make:** these are properties of the *configuration*, so a change is always pool-wide and always versioned.

1. On `hp-mms-scratch` → **Session hosts** → **Manage session host configuration** → **Edit**.
2. **Image.** Select **See all images** → your Azure Compute Gallery → move from version `1.0.0` to `1.1.0`. Call out the rules while the picker is open:
   - Marketplace, Compute Gallery, or managed image.
   - Must be supported for AVD and match the VM generation.
   - At least two replicas recommended.
   - Same subscription as the host pool.
   - A gallery image with a **purchase plan** loses the plan on update — check first with `Get-AzGalleryImageVersion` or `az sig image-version show`.
3. **Virtual machine size.** Move up (or down) one size — e.g. `D2as_v5` → `D4as_v5`. Tie it to the right-sizing scenario from the deck.
4. **OS disk type.** Switch Standard SSD → **Premium SSD**. Two things to say: Premium is the production recommendation, and the **OS disk size cannot be changed here** — it follows the gallery image definition. The new disk is named `SessionHostName-DateTime_Hash`.
5. **Security type.** Open the dropdown and *narrate without changing it* (unless your image is gen 2 and you want the full demo): Trusted launch auto-selects secure boot and vTPM; Confidential VMs add integrity monitoring and you cannot opt out of vTPM.
6. **Domain to join.** Show the Key Vault pickers for the domain-join account and the optional OU path. Say the constraint plainly: **you cannot change the directory during an update.**
7. **Custom configuration.** Paste your script URL. This is the escape hatch for deploy-time customization — keep the script fast, idempotent and logging to a share.
8. Continue through **Schedule** → **Notifications** → **Review** and select **Update**.
9. Back on **Session hosts**, show the configuration **version has incremented** and every host now shows a **warning icon on Current Version** because it is behind **Target Version**.

**Callout for the room:** everything a person hand-applied to a host — files, registry keys, certificates — is gone after this. Put it in the image, in Intune/GPO, or in the custom configuration script.

---

## Demo 3 — The same update in PowerShell (~8 min, after slide "Demo 3")

**Point to make:** everything in the portal is automatable, and this is how it goes in your pipeline.

Open Cloud Shell (PowerShell) or a local session with `Az.DesktopVirtualization` 5.3.0+.

```powershell
$rg   = 'rg-mms-avd'
$pool = 'hp-mms-scratch'

# 1. Read the current configuration
Get-AzWvdSessionHostConfiguration -ResourceGroupName $rg -HostPoolName $pool |
    Format-List Version, ImageInfo*, VMSizeId, DiskType, DomainInfo*

# 2. Change only what you need — every parameter you omit is left alone
Update-AzWvdSessionHostConfiguration `
    -ResourceGroupName $rg `
    -HostPoolName      $pool `
    -VMSizeId          'Standard_D4as_v5' `
    -DiskType          'Premium_LRS'

# 3. Confirm the change landed and a new version was stamped
Get-AzWvdSessionHostConfiguration -ResourceGroupName $rg -HostPoolName $pool |
    Format-List Version, VMSizeId, DiskType

# 4. Optional: set the defaults the update will run with
Update-AzWvdSessionHostManagement `
    -ResourceGroupName            $rg `
    -HostPoolName                 $pool `
    -UpdateMaxVmsRemoved          2 `
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

**Say these three things while the cmdlets run**

- These cmdlets are **preview** and need **Az.DesktopVirtualization 5.3.0 or later**.
- `-UpdateDeleteOriginalVM $true` is the recommended setting — otherwise you own the cleanup of the old VMs.
- Time zone values come from `Get-TimeZone`, using the **StandardName** property.
- **Once an update is scheduled you cannot edit it.** To change anything, cancel it and schedule a new one.

**Tip:** verify exact parameter names against your installed module version before the session (`Get-Help Update-AzWvdSessionHostManagement -Full`) — preview cmdlets move.

---

## Demo 4 — Monitor, pause, resume, cancel (~10 min, after slide "Demo 4")

**Point to make:** you are never locked in mid-update, but cancel has a real cost.

1. Return to `hp-mms-demo` → **Session hosts**. The update from demo 1 should now be past the initial host.
2. Show the **blue banner**, select **Refresh** and read the progress. Point at the host list: replaced hosts carry the `SessionHostName-DateTime` naming on their Azure resources while the **OS host name is unchanged**.
3. Select **Manage session host update** → **Pause**. Refresh after ~20 seconds — the status takes about that long to settle. Explain that pause lets the **batch in flight finish** first.
4. Select **Resume** and show it continuing from where it stopped. Mention: an update left paused for **two weeks is cancelled automatically**.
5. Show the **Cancel** and **Retry** buttons without pressing Cancel on the good pool. Give the warning verbatim: a cancelled update **cannot be resumed**, and a pool cancelled mid-flight can end up with **mixed OS versions or mixed domains** — schedule a replacement update immediately.
6. Switch to `hp-mms-scratch` and show a **cancelled or failed** update if you staged one, including the **Retry** path. Note that a host pool with a failed update **cannot be deleted until the update is cancelled**.
7. Two rules to repeat: **do not remove VMs from the pool** and **do not touch drain mode** while an update is running — the service owns drain mode for the duration and resets it at the end.
8. Optional 30-second detour: **Azure Monitor → Activity log** filtered to the host pool, showing the same operations from the ARM side.

---

## Demo 5 — Prove it with Kusto (~8 min, after slide "Demo 5")

**Point to make:** "did it work, how long did it take, and what broke" are all queryable.

Open **Log Analytics** on the workspace attached to `hp-mms-history`. Have both queries **pre-pasted in tabs** — do not type Kusto on stage.

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

Show a real `CodeSymbolic` from your lab. If you have one, `AgentRegistrationFailureGeneric` is the perfect closer: large batch sizes can produce it intermittently, and retrying the update usually clears it.

**Close the demo block by naming the fix for the classic failure:** if the source image was captured from a running session host, delete `C:\packages\plugin` before capturing — that folder blocks the DSC extension that joins updated VMs to the host pool.

---

## Q&A ammunition (questions this room always asks)

| Question | Answer |
|---|---|
| Can I update one host? | No. Changes are pool-wide, driven by the session host configuration. |
| Do I lose my AD computer objects? | No. They are reused, the OS host name is unchanged, and existing GPOs still apply. Change domain or OU and you must clean up orphaned objects yourself. |
| What about personal/dedicated pools? | Session host update targets **pooled** host pools with a session host configuration. |
| Does it work in Azure Government or 21Vianet? | No. Global Azure cloud only today. |
| Can I run updates on several pools at once? | Yes across pools; only one update running or scheduled **per pool** at a time. |
| Will AVD Insights keep working? | The Azure Monitor agent is not reinstalled automatically — deploy it with Azure Policy. |
| What if all my hosts are deallocated to save cost? | Supported — the existing power state and drain mode are honoured. |
| Can I change OS disk size? | Not in the update. It follows the gallery image definition. |
| How long will it take? | About 20 minutes per host; one initial host, then batches of your chosen size. |

---

## Sources

- Microsoft Learn — *Session host update for Azure Virtual Desktop*
- Microsoft Learn — *Update session hosts using session host update in Azure Virtual Desktop*
- Microsoft Learn — *Example diagnostic queries for session host update in Azure Virtual Desktop*
- Microsoft Learn — *Troubleshoot session host update*
