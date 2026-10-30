# Azure Virtual Desktop Hybrid — MMS Demo Runbook

Companion to the session **"Azure Virtual Desktop Hybrid | Under The Hood: Features, Benefits, and the Fine Print"**
Presenters: Adam Nichols, Chris Cavazos · 5 demos · ~49 minutes of demo time inside a 60-75 minute slot

> AVD Hybrid is **not** AVD on Azure Local. There's no resource bridge, no custom location, no per-vCPU Azure Local fee, and no Session Host Configuration. Every session host here is a plain Azure Arc-enabled machine — a VM on whatever hypervisor you already run, or a physical server — registered to a host pool through the AVD Arc extension.

---

## 0. Prepare a private lab configuration

This is a **public template**, not a record of current infrastructure or readiness.
`DEMO-AVD-01/02/03/04`, resource names and paths below are sample labels only.
No tenant, subscription, guest address, SMBIOS UUID, VMID or installer hash is
provided for a real environment. The synthetic fixture under `tests/` is for
**offline tests only**; never use it for an Azure operation or readiness claim.

1. Copy `MmsAvdHybrid.config.example.json` to `MmsAvdHybrid.private.json` on a
   trusted operator machine. `*.private.json` and status reports are ignored here;
   preferably keep private bindings and generated inventories **outside the repo**.
   Do not add credentials or registration tokens to this file.
2. Fill in the actual `SubscriptionId`, `TenantId`, `Domain`, resource group, location,
   Live/Ready pool names and all four exact host bindings (`Name`, hardware SMBIOS
   `Uuid`, integer `Vmid`). Use the configured names consistently in this runbook.
   Live requires two hosts; Ready and optional Arc onboarding have distinct names,
   UUIDs and VMIDs. VMID is an operator label, not a substitute for hardware identity.
3. Set `MsiPath` to a staged Microsoft-signed Azure Connected Machine Agent MSI and
   `MsiSha256` to the independently reviewed hash of those exact bytes. Get the MSI
   from Microsoft, verify its Authenticode signature and publisher, then calculate
   `Get-FileHash -Algorithm SHA256`. Do not copy a published example digest as trust.
4. Review the entire config before distributing it privately alongside both scripts
   and `MmsAvdHybrid.Config.ps1`. Config is a trusted allowlist, not proof of authority:
   replacing it intentionally retargets the demo. Restrict its write permissions.
   The scripts reject missing/invalid config, duplicate identities and equal pools.
5. In **each** guest/operator PowerShell process explicitly select that file:

   ```powershell
   $env:MMS_AVD_HYBRID_CONFIG = 'C:\Private\MmsAvdHybrid.private.json'
   # Alternatively pass -ConfigPath to each script; JSON does not load itself.
   ```

Use supported Windows 11 Enterprise single-session guests on your chosen hypervisor,
AD/hybrid joined to the configured tenant. Confirm licensing, endpoints and OS support
against Microsoft documentation for your deployment. No disk placement, domain, guest
address or hypervisor inventory is prescribed by this sample.

| Config role | Sample host label | State before demos |
|---|---|---|
| `LiveHosts[0]` | `DEMO-AVD-01` | Arc Connected, no AVD evidence |
| `LiveHosts[1]` | `DEMO-AVD-02` | Arc Connected, no AVD evidence |
| `ReadyHost` | `DEMO-AVD-03` | Ready pool, extension Succeeded, broker Available; test Windows App |
| `ArcHost` | `DEMO-AVD-04` | Optional separate manual Arc onboarding only; not a Live target |

Pre-stage distinct Live/Ready host pools, workspace/application groups, an attached
managed identity with Reader on the Arc resource group, and approved user assignments.
Do not create duplicate grants or reconnect an already-connected host. Install
`Az.Accounts` on Live guests in advance; presenter status requires Azure CLI or
Az.Accounts and Graph read permission. ConfigMgr and roaming profiles are **not**
prerequisites. This demo uses local profiles; don't claim cross-host roaming.

Run elevated Windows PowerShell 5.1 on each exact Live guest:

```powershell
.\Invoke-MMSAVDHybridLive.ps1 -Action Check
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -WhatIf
# Human-only, explicitly authorized on-stage step:
.\Invoke-MMSAVDHybridLive.ps1 -Action Register -Confirm
.\Invoke-MMSAVDHybridLive.ps1 -Action Status
```

Check/WhatIf read only local prerequisites; **no** sign-in, cloud reads or writes.
Register checks the authenticated tenant/subscription against ARM, the guest and
Arc hardware identity, both pools and existing extensions before writing. Run
sequentially: each Register rotates the **shared** Live pool token for four hours.
Wait for the prior extension to consume it before rotating again. Tokens stay in
memory and extension `protectedSettings`, never public settings or disk. Do not
turn on step/HTTP tracing or inspect secret variables. Existing logging policies
are outside this script's control. Accepted extension requests are not proof of
registration, broker Available or functional user sign-in; use Status then test
Windows App. Do not delete stale evidence or retry blindly to bypass a guard.

For the optional configured `ArcHost`, use `Connect-MMSAVDHYB04Arc.ps1` with the
same Check → Register -WhatIf → Register -Confirm workflow. The retained filename
is a demo label, **not** a fixed host binding. This installs the pinned/signed MSI
if needed and manually connects only that hostname/UUID via device authentication;
it does not register AVD or assign a pool. Verify the exact resource in Azure portal
following local `ConnectedLocal`. A nested shell does not elevate: use **Run as
administrator**. Never share device codes, tokens or passwords in chat. Stop and
inspect agent logs/ACLs if connection fails; don't weaken guards or retry blindly.

Presenter-side read-only inventory (requires the same private config):

```powershell
.\Show-MMSAVDHybridStatus.ps1 -Phase Staged -NoLogin -JsonPath C:\Private\avd-status.json
```

It checks tenant/subscription authority before inventory reads. Without `-NoLogin`
it may prompt for device authentication. Reports contain private resource inventory:
keep them out of source control. Fixture mode is explicitly offline and cannot prove
live readiness. No previous lab's success counts apply to a new environment.

Before the session confirm: Live empty; Ready exactly one expected Available host;
working secure channels; guest `DomainJoined`/`AzureAdJoined` and tenant; Arc hardware
UUID mapping (`vmUuid` / ARM `detectedProperties.vmuuidEsu`, not agent `vmId`); both
endpoint lists; identity Reader grant; licensing; actual Windows App sign-in; fallback
recording. Allow up to 15 minutes after extension Succeeded for broker Available.

---

## Demo 1 — Anatomy of a hybrid host pool (~10 min, after slide "Demo 1")

**Point to make:** a Hybrid host pool looks almost empty on purpose — there's no VM-creation wizard because AVD never provisions the machine.

1. Azure portal → **Azure Virtual Desktop** → **Host pools** → show the existing **Live** and **Ready** pooled/Standard host pools. Do not recreate them on stage; there is no Session Host Configuration for Hybrid.
2. On **Identity**, show the existing user-assigned identity `id-avd-demo` on both pools; it reads the Arc resource group.
3. Explain that the pool did not create any of the three Proxmox VMs — their lifecycle is independent of AVD.
4. Show the existing `ws-avd-demo` workspace and the two desktop application groups.
5. Open **Session hosts**: **Live** should be empty; **Ready** should show `DEMO-AVD-03.ad.example.test`. Say: *"A Hybrid host pool is just a mailbox waiting for machines to register themselves — AVD doesn't create them."*
6. In **Azure Arc → Machines**, show all three Connected. `DEMO-AVD-01/02` have no AVD extension yet; `DEMO-AVD-03` is the pre-staged Ready desktop. This sets up demo 3 without consuming its registration step.

**Talk track:** contrast this with a normal AVD host pool, where the wizard lets you size, image, and create VMs right there. Hybrid deliberately has none of that — the machine's whole lifecycle already happened before AVD ever heard about it.

---

## Demo 2 — Pre-flight validation in five minutes (~8 min, after slide "Demo 2")

**Point to make:** there are two separate endpoint lists and one role assignment — almost every real failure traces back to one of these three things.

1. On `DEMO-AVD-01`, run the Arc connectivity check:
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
   $config = Get-Content -LiteralPath $env:MMS_AVD_HYBRID_CONFIG -Raw | ConvertFrom-Json
   # Verify your selected Azure tenant/subscription before any manual RBAC change.
   $identity   = Get-AzUserAssignedIdentity -ResourceGroupName $config.ResourceGroup -Name '<your-reviewed-managed-identity-name>'
   $principalId = $identity.PrincipalId # A user-assigned identity's principal, not the host pool's null system-assigned principal
   New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Reader' -ResourceGroupName $config.ResourceGroup
   ```
4. Confirm the machine's join type is compliant for its OS: Windows Server must be AD DS or hybrid-joined (never Entra-only); Windows 10/11 can be Entra ID-joined, AD DS-joined, or hybrid-joined.

**Talk track:** the two failures that eat the most time in the field are a missing Reader grant on the Arc resource group and confusing the AVD URL list with the Arc URL list. Both are checkable in under five minutes with what's on this slide.

---

## Demo 3 — Control plane, then the first session hosts (~12 min, after slide "Demo 3")

**Point to make:** this is the whole trick — Arc-enable, grant access, register, wait. Nothing here creates a VM.

1. `DEMO-AVD-01` is already Arc-connected. Show `azcmagent show --json` and narrate the initial connection; **do not rerun `azcmagent connect` on the connected host**:
   ```powershell
   azcmagent show --json
   ```
2. In **Azure Arc → Machines**, show the machine already **Connected**; the live action is AVD registration, not Arc onboarding.
3. On `DEMO-AVD-01`, preview the exact guest and Live pool before any Azure sign-in or registration-token rotation:
   ```powershell
   Set-Location C:\Scripts
   .\Invoke-MMSAVDHybridLive.ps1 -Action Check
   .\Invoke-MMSAVDHybridLive.ps1 -Action Register -WhatIf
   ```
4. Run the explicit registration step from the **same host** and complete the Azure device sign-in yourself (never paste a code into chat). The script checks both pools, generates a four-hour token for the **Live** pool, then submits the Arc extension. Do **not** also click Add extension in the portal, which would duplicate the operation:
   ```powershell
   .\Invoke-MMSAVDHybridLive.ps1 -Action Register -Confirm
   ```
5. In the portal, show `DEMO-AVD-01` → **Extensions** moving to Succeeded; use `.\Invoke-MMSAVDHybridLive.ps1 -Action Status` in the same PowerShell session to inspect progress. An accepted request is not a registered or usable desktop.
6. Jump to the host pool's **Session hosts** blade and refresh. If `DEMO-AVD-01` isn't **Available** yet (it can take up to 15 minutes), switch to the **pre-staged** `DEMO-AVD-03` and show that one **Available** instead — be upfront that this is the same process, just further along.
7. Verify the test user's existing application-group assignment; add it only if absent. Have that user connect through Windows App to prove the loop closes.

**Talk track while it runs:** nothing here provisions or images a VM — AVD only starts caring once a machine with the extension installed asks to register. Compare this explicitly to slide "Deploy in this order, or rebuild": provision & Arc-enable, create the control plane, grant access & register, assign & validate.

**Leave `DEMO-AVD-01`'s registration running.** Check back on it during demo 5's wrap-up.

---

## Demo 4 — Session hosts as code (~10 min, after slide "Demo 4")

**Point to make:** the guarded on-host script performs the same control-plane registration with explicit checks and a protected token. Do not run the raw cmdlets from an older guide as well as this script.

```powershell
Set-Location C:\Scripts   # on DEMO-AVD-02 only, in Windows PowerShell 5.1
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
- Run this only against another deliberately staged **Live** machine. `DEMO-AVD-03` is already in **Ready**; do not re-run the Live registration snippet against it.

---

## Demo 5 — Shortpath and the user experience (~9 min, after slide "Demo 5")

**Point to make:** AVD still brokers a desktop on an Arc-enabled machine. This lab uses **local profiles**; profile roaming is deliberately outside the demo.

1. Connect to the pre-staged, already-**Available** host from **Windows App**. A live user connection is the proof; the portal status alone is not.
2. Open the connection information flyout in the client and point out **RDP Shortpath** negotiated over UDP — call out that this works the same way it does for a cloud-hosted session host, direct across the LAN. If it negotiated TCP instead, show that honestly rather than claiming UDP.
3. Open `powershell.exe` in the session and run `hostname` and `whoami` to show the Arc-enabled host and the signed-in demo user. No network profile container is involved.
4. Disconnect and reconnect to the **same** Ready desktop to show the broker returns to that host and session. Do not narrate profile roaming across hosts; local desktop settings are scoped to that machine.
5. **Optional stretch demo:** block UDP 3390 at the host's firewall, reconnect, and show Shortpath fail to negotiate and fall back to RDP over TCP — a good "what does it look like when it's broken" moment if time allows.
6. Circle back to `DEMO-AVD-01` from demo 3 — by now its registration should have finished. Refresh the **Session hosts** blade one more time and show it landed on its own, no extra clicks.

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

## Offline verification of this template

From this directory, using PowerShell (no Az modules or cloud access required):

```powershell
pwsh -NoProfile -File ./tests/Test-MMSAVDHybridLive.ps1
pwsh -NoProfile -File ./tests/Test-MMSAVDHYB04Arc.ps1
pwsh -NoProfile -File ./tests/Test-MmsAvdHybridConfig.ps1
```

The fixture contains deliberately synthetic identities and a fake hash, **not** a
usable installer pin. Tests cover exact-host/UUID rejection, domain/tenant checks,
local-only Check/WhatIf, both-pool/extension write gates, protected token handling,
installer signature/hash rechecks, config failures and read-only status authority.
These are offline tests, not Windows guest execution or an Azure integration test.
PowerShell 5.1 syntax analysis is not the same as running Windows PowerShell 5.1.
A cleanup commit removes bindings from the current tree only; older commits, PRs,
caches or copies can still contain previously published inventory. No history
rewrite, credential rotation or infrastructure cleanup is performed by this template.
