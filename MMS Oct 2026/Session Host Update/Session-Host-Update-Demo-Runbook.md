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

## Individual demo scripts — open these on stage

These five files are the **presenter scripts and source of truth** for the demo steps. [Open the GitHub demo folder index](demos/README.md) for a compact navigation view. Keep the common subscription/lab preparation and readiness gates in this runbook; do not skip them just because a cue card opens.

1. [Demo 1 — Portal update](demos/01-portal-reset.md): start the four-host `hp-mms-demo` update (batch size two). This is the **same update** monitored in Demo 4.
2. [Demo 2 — Portal image/size/disk change](demos/02-portal-change.md): use the independent one-host `hp-mms-change` pool.
3. [Demo 3 — PowerShell update](demos/03-powershell-update.md): presenter cues plus [guarded `03-update.ps1`](demos/03-update.ps1). Default `Check` is read-only; `-Action Run` changes the one-host `hp-mms-cli` pool **only after confirmation**. `-WhatIf` is an offline preview, not a cloud readiness check.
4. [Demo 4 — Monitor, pause, resume](demos/04-monitor-control.md): watch the **Demo 1** update; use a verified recording as the primary path if its live timing does not cooperate.
5. [Demo 5 — Log Analytics diagnostics](demos/05-diagnostics.md): independent [success](demos/05-success.kql) and [failure](demos/05-errors.kql) Kusto queries. Query B remains a readiness gate until it returns a real failure row or a verified recording exists.

`check_lab.py` now reads the two `.kql` files directly; copying them into slides or the portal must not silently change the tested source. All update actions require starting and checking the parked lab **before** the event; never start the generalized image-source VMs.

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
