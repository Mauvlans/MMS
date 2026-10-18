# Azure Virtual Desktop Hybrid — MMS Demo Runbook

Companion to the session **"Azure Virtual Desktop Hybrid | Under The Hood: Features, Benefits, and the Fine Print"**
Presenters: Adam Nichols, Chris Cavazos · 5 demos · ~49 minutes of demo time inside a 60-75 minute slot

> AVD Hybrid is **not** AVD on Azure Local. There's no resource bridge, no custom location, no per-vCPU Azure Local fee, and no Session Host Configuration. Every session host here is a plain Azure Arc-enabled machine — a VM on whatever hypervisor you already run, or a physical server — registered to a host pool through the AVD Arc extension.

---

## 0. Lab build (do this before you travel)

**Current MMS lab:** subscription `e6ab1306-dfc4-4975-9f15-1df30c4699e2`, resource group `rg-MMS-AVDHybrid-UnderTheHood` in `westus3`. The **Live** pool is `hp-MMS-AVDHybrid-UnderTheHood`; the separate **Ready** pool is `hp-MMS-AVDHybrid-UnderTheHood-Ready`. Both use the existing `ws-MMS-AVDHybrid-UnderTheHood` workspace and their own desktop application groups. All three Windows 11 Enterprise single-session VMs run on `PRX-03` local NVMe, are joined to `AD.Mauvlan.Net` and hybrid Entra-joined, and are Azure Arc-connected. The Live pool stays empty until demos 3 and 4; only the Ready host is registered before the session. Arc-enabling is already done, so narrate that step rather than reconnecting a machine live.

| Machine / Proxmox VMID | Guest IPv4 | AVD plan |
|---|---|---|
| `MMS-AVDHYB-01` / `122` | `10.0.10.217` | Arc-connected; **no AVD extension/registration** until live demo 3 |
| `MMS-AVDHYB-02` / `123` | `10.0.10.223` | Arc-connected; **no AVD extension/registration** until scripted demo 4 |
| `MMS-AVDHYB-03` / `124` | `10.0.10.250` | Pre-register in **Ready** and verify Available before the session; fallback desktop for demo 5 |

The guests currently report Windows build `26300` and ConfigMgr client `5.00.9146.1027` assigned to site `MVN`. The boot/EFI/TPM disks are on `PRX-03-MVNE2-XFS`, **not `UNAS_PRO_8`**; the attached UNAS references are installer ISOs only. Never place a new runtime disk on `UNAS_PRO_8` without Adam's explicit approval. Build 26300 is not listed in [Microsoft's ConfigMgr Windows 11 client support matrix](https://learn.microsoft.com/en-us/intune/configmgr/core/plan-design/configs/support-for-windows-11); the agent's actual registration is verified, but that is not an official OS-support claim.

**Read-only preflight (2026-10-18):** `Show-MMSAVDHybridStatus.ps1 -Phase Staged` returned `PASS=9 READY=1 STAGED=4 FAIL=0 ERROR=0`. The Ready session host reported **Available**, zero sessions and a recent heartbeat; the Live pool was empty. This proves registration and broker status, **not** a successful Windows App sign-in or stable desktop. Complete that hands-on test before the presentation.

**Staged on-host execution:** the same guarded `C:\Scripts\Invoke-MMSAVDHybridLive.ps1` is on `MMS-AVDHYB-01` (VMID 122) and `MMS-AVDHYB-02` (VMID 123) **only**. `MMS-AVDHYB-03` is already in Ready and must not run it. Start an elevated Windows PowerShell 5.1 session with a **process-only** execution-policy bypass (`powershell.exe -NoProfile -ExecutionPolicy Bypass`), then run `-Action Check` and `-Action Register -WhatIf` without signing in. Only `-Action Register -Confirm` begins the interactive device sign-in and Azure writes; perform that on stage, one host at a time. The script uses the preinstalled `Az.Accounts` module and stores no credential or registration token in the PS1. `-Action Status` is read-only and uses the same signed-in PowerShell process. The separate `Show-MMSAVDHybridStatus.ps1` remains a **presenter-side** status tool, not a guest registration script.

**Required in the lab before the session**

- [ ] The **Live** standard pool still has **zero** session hosts; the **Ready** standard pool has exactly `MMS-AVDHYB-03.AD.Mauvlan.Net` reporting Available. Session Host Configuration is not an option for Hybrid pools.
- [ ] A **workspace** and **application group**, with the app group added to the workspace.
- [ ] A **managed identity** (system- or user-assigned) attached to the host pool on the **Identity** tab.
- [ ] The existing managed identity's **Reader** assignment on the Arc resource group still exists; show it in demo 3, but don't create a duplicate grant.
- [ ] `Az.DesktopVirtualization`, `Az.ConnectedMachine`, and `Az.ManagedServiceIdentity` PowerShell modules installed on the demo machine, or Cloud Shell ready.
- [ ] `azcmagent show --json` reports Connected on **each** of VMIDs 122/123/124; confirm the exact Arc resource and matching VM UUID, not just an installer exit code.
- [ ] Each guest reports a working AD secure channel, `DomainJoined: YES`, `AzureAdJoined: YES`, and an Entra `DeviceId` matching its synced AD computer GUID. Do not equate the presence of an Entra device object with completed guest join.
- [ ] ConfigMgr (`MVN`, management point `MVN-MECM.AD.Mauvlan.Net`) shows each client active with the same GUID as the guest; this manages the lab machines but is not an AVD prerequisite.
- [ ] **Local profiles** on each demo host for this session; do not depend on an FSLogix SMB share or claim profiles roam between hosts. Existing VHDX files are preserved outside the demo path for rollback.
- [ ] **Microsoft.DesktopVirtualization** resource provider registered on the subscription.
- [ ] **Desktop Virtualization Contributor** on you (or whoever drives the portal), and **User Access Administrator** if you'll assign users live.
- [ ] Two endpoint checklists open in tabs: the [AVD required URLs](https://learn.microsoft.com/en-us/azure/virtual-desktop/required-fqdn-endpoint) list and the [Azure Arc network endpoints](https://learn.microsoft.com/en-us/azure/azure-arc/network-requirements-consolidated) list — these are **not the same list**, and mixing them up is the most common day-one failure.
- [ ] Windows App installed and signed in on the machine you'll use for demo 5.
- [ ] RDS CAL or the right M365/Windows Enterprise/VDA entitlement confirmed for whichever OS you're demoing, plus a spare AVD Hybrid service user license.
- [ ] Azure portal, Azure Arc > Machines, and the host pool's Session hosts blade **pre-loaded in tabs**.
- [ ] Screen recording of a full Arc-enable → extension succeeded → host Available cycle as a **fallback if venue Wi-Fi can't reach Azure**.

**Timing reality check.** After the AVD Arc extension reports **Succeeded**, the host can take **up to 15 minutes** to show **Available** in the host pool. Kick off demo 3's registration early and let it run in the background while you talk through demo 4 and 5 — don't wait on stage.

---

## Demo 1 — Anatomy of a hybrid host pool (~10 min, after slide "Demo 1")

**Point to make:** a Hybrid host pool looks almost empty on purpose — there's no VM-creation wizard because AVD never provisions the machine.

1. Azure portal → **Azure Virtual Desktop** → **Host pools** → show the existing **Live** and **Ready** pooled/Standard host pools. Do not recreate them on stage; there is no Session Host Configuration for Hybrid.
2. On **Identity**, show the existing user-assigned identity `id-MMS-AVDHybrid-UnderTheHood` on both pools; it reads the Arc resource group.
3. Explain that the pool did not create any of the three Proxmox VMs — their lifecycle is independent of AVD.
4. Show the existing `ws-MMS-AVDHybrid-UnderTheHood` workspace and the two desktop application groups.
5. Open **Session hosts**: **Live** should be empty; **Ready** should show `MMS-AVDHYB-03.AD.Mauvlan.Net`. Say: *"A Hybrid host pool is just a mailbox waiting for machines to register themselves — AVD doesn't create them."*
6. In **Azure Arc → Machines**, show all three Connected. `MMS-AVDHYB-01/02` have no AVD extension yet; `MMS-AVDHYB-03` is the pre-staged Ready desktop. This sets up demo 3 without consuming its registration step.

**Talk track:** contrast this with a normal AVD host pool, where the wizard lets you size, image, and create VMs right there. Hybrid deliberately has none of that — the machine's whole lifecycle already happened before AVD ever heard about it.

---

## Demo 2 — Pre-flight validation in five minutes (~8 min, after slide "Demo 2")

**Point to make:** there are two separate endpoint lists and one role assignment — almost every real failure traces back to one of these three things.

1. On `MMS-AVDHYB-01`, run the Arc connectivity check:
   ```powershell
   azcmagent show
   azcmagent check
   ```
   Narrate: this is the Arc-side equivalent of the AVD Agent URL Tool, and it checks a **different** URL list than AVD itself needs.
2. Separately confirm the standard AVD required URLs are reachable on 443 (use the AVD Agent URL Tool, or a quick loop):
   ```powershell
   $avdUrls = @('login.microsoftonline.com','www.microsoft.com','wvdportalstorageblob.blob.core.windows.net')
   foreach ($u in $avdUrls) { Test-NetConnection -ComputerName $u -Port 443 | Select-Object ComputerName, TcpTestSucceeded }
   ```
3. In the portal, open the host pool's managed identity → jump to the **Arc resource group → Access control (IAM) → Role assignments** and confirm **Reader** is present for that identity. If it's missing, add it live:
   ```powershell
   $identity   = Get-AzUserAssignedIdentity -ResourceGroupName 'rg-MMS-AVDHybrid-UnderTheHood' -Name 'id-MMS-AVDHybrid-UnderTheHood'
   $principalId = $identity.PrincipalId # A user-assigned identity's principal, not the host pool's null system-assigned principal
   New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Reader' -ResourceGroupName 'rg-MMS-AVDHybrid-UnderTheHood'
   ```
4. Confirm the machine's join type is compliant for its OS: Windows Server must be AD DS or hybrid-joined (never Entra-only); Windows 10/11 can be Entra ID-joined, AD DS-joined, or hybrid-joined.

**Talk track:** the two failures that eat the most time in the field are a missing Reader grant on the Arc resource group and confusing the AVD URL list with the Arc URL list. Both are checkable in under five minutes with what's on this slide.

---

## Demo 3 — Control plane, then the first session hosts (~12 min, after slide "Demo 3")

**Point to make:** this is the whole trick — Arc-enable, grant access, register, wait. Nothing here creates a VM.

1. `MMS-AVDHYB-01` is already Arc-connected. Show `azcmagent show --json` and narrate the initial connection; **do not rerun `azcmagent connect` on the connected host**:
   ```powershell
   azcmagent show --json
   ```
2. In **Azure Arc → Machines**, show the machine already **Connected**; the live action is AVD registration, not Arc onboarding.
3. On `MMS-AVDHYB-01`, preview the exact guest and Live pool before any Azure sign-in or registration-token rotation:
   ```powershell
   Set-Location C:\Scripts
   .\Invoke-MMSAVDHybridLive.ps1 -Action Check
   .\Invoke-MMSAVDHybridLive.ps1 -Action Register -WhatIf
   ```
4. Run the explicit registration step from the **same host** and complete the Azure device sign-in yourself (never paste a code into chat). The script checks both pools, generates a four-hour token for the **Live** pool, then submits the Arc extension. Do **not** also click Add extension in the portal, which would duplicate the operation:
   ```powershell
   .\Invoke-MMSAVDHybridLive.ps1 -Action Register -Confirm
   ```
5. In the portal, show `MMS-AVDHYB-01` → **Extensions** moving to Succeeded; use `.\Invoke-MMSAVDHybridLive.ps1 -Action Status` in the same PowerShell session to inspect progress. An accepted request is not a registered or usable desktop.
6. Jump to the host pool's **Session hosts** blade and refresh. If `MMS-AVDHYB-01` isn't **Available** yet (it can take up to 15 minutes), switch to the **pre-staged** `MMS-AVDHYB-03` and show that one **Available** instead — be upfront that this is the same process, just further along.
7. Verify the test user's existing application-group assignment; add it only if absent. Have that user connect through Windows App to prove the loop closes.

**Talk track while it runs:** nothing here provisions or images a VM — AVD only starts caring once a machine with the extension installed asks to register. Compare this explicitly to slide "Deploy in this order, or rebuild": provision & Arc-enable, create the control plane, grant access & register, assign & validate.

**Leave `MMS-AVDHYB-01`'s registration running.** Check back on it during demo 5's wrap-up.

---

## Demo 4 — Session hosts as code (~10 min, after slide "Demo 4")

**Point to make:** the guarded on-host script performs the same control-plane registration with explicit checks and a protected token. Do not run the raw cmdlets from an older guide as well as this script.

```powershell
Set-Location C:\Scripts   # on MMS-AVDHYB-02 only, in Windows PowerShell 5.1
.\Invoke-MMSAVDHybridLive.ps1 -Action Check
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -WhatIf
# First let demo 3's extension finish using its token; rotating the shared Live token early can disrupt it.
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -Confirm
# Wait for the extension/broker to progress, then in this same PowerShell process:
.\Invoke-MMSAVDHybridLive.ps1 -Action Status
```

**Say these three things while it runs**

- The on-host script binds the Windows hostname and SMBIOS UUID to the exact Arc machine and **Live** pool, checks for existing AVD registration, and submits the extension once. Do not run it concurrently on both Live hosts: each explicit Register rotates a shared host-pool token.
- `Az.Accounts` is already installed on both Live guests. The script needs an interactive operator with Azure write permissions; local Check/WhatIf need no Azure sign-in.
- Nothing about the machine's OS image, size, or disk is visible here — because AVD Hybrid never touched any of that. Your provisioning tool owns it entirely.
- Run this only against another deliberately staged **Live** machine. `MMS-AVDHYB-03` is already in **Ready**; do not re-run the Live registration snippet against it.

---

## Demo 5 — Shortpath and the user experience (~9 min, after slide "Demo 5")

**Point to make:** AVD still brokers a desktop on an Arc-enabled machine. This lab uses **local profiles**; profile roaming is deliberately outside the demo.

1. Connect to the pre-staged, already-**Available** host from **Windows App**. A live user connection is the proof; the portal status alone is not.
2. Open the connection information flyout in the client and point out **RDP Shortpath** negotiated over UDP — call out that this works the same way it does for a cloud-hosted session host, direct across the LAN. If it negotiated TCP instead, show that honestly rather than claiming UDP.
3. Open `powershell.exe` in the session and run `hostname` and `whoami` to show the Arc-enabled host and the signed-in demo user. No network profile container is involved.
4. Disconnect and reconnect to the **same** Ready desktop to show the broker returns to that host and session. Do not narrate profile roaming across hosts; local desktop settings are scoped to that machine.
5. **Optional stretch demo:** block UDP 3390 at the host's firewall, reconnect, and show Shortpath fail to negotiate and fall back to RDP over TCP — a good "what does it look like when it's broken" moment if time allows.
6. Circle back to `MMS-AVDHYB-01` from demo 3 — by now its registration should have finished. Refresh the **Session hosts** blade one more time and show it landed on its own, no extra clicks.

**Talk track:** Hybrid keeps brokering, Windows App, and supported transport features in Azure; the machine, hypervisor, image, and profile strategy remain yours. This demo intentionally chooses local profiles, not FSLogix, so don't promise cross-host profile continuity.

---

## Q&A ammunition (questions this room always asks)

| Question | Answer |
|---|---|
| Is this the same as AVD on Azure Local? | No. Separate products. No resource bridge, no custom location, no per-vCPU Azure Local fee, no Session Host Configuration. |
| Can I use Windows 10/11 or Server multi-session? | No. AVD Hybrid supports single-session Windows 10/11 Enterprise or Windows Server only. |
| Does autoscale or Start VM on Connect work? | No. Neither does power management. You own the entire machine lifecycle, always. |
| What hypervisor do I need? | Any that runs a supported Windows OS, or a physical server. Azure Arc doesn't care what's underneath. |
| Can Windows Server session hosts be Microsoft Entra ID-only joined? | No — the RDS licensing server dependency requires AD DS or hybrid join. Windows 10/11 hosts can be Entra ID-only. |
| How do I patch session hosts? | Entirely your own tooling and schedule. There's no scheduled session host update feature for Hybrid pools. |
| A host won't show Available — now what? | Check the extension status first, then confirm the managed identity has Reader on the Arc resource group, then re-check both endpoint lists. Allow up to 15 minutes after Succeeded. |
| What's the licensing model? | User entitlement (RDS CAL or the matching M365/Windows Enterprise/VDA license) **plus** a separate Azure Virtual Desktop Hybrid service user license. |
| Can I mix Hybrid and regular Azure session hosts in one pool? | Not recommended — plan separate pools per platform so load balancing and licensing stay predictable. |

---

## Sources

- Microsoft Learn — *Azure Virtual Desktop Hybrid overview*
- Microsoft Learn — *Deploy Azure Virtual Desktop Hybrid on-premises*
- Microsoft Learn — *Built-in Azure RBAC roles for Azure Virtual Desktop*
- Microsoft Learn — *Azure Arc-enabled servers overview and agent overview*
- Microsoft Learn — *Azure Virtual Desktop required URLs* and *Azure Arc network requirements*
- Microsoft Learn — *Licensing Azure Virtual Desktop*
