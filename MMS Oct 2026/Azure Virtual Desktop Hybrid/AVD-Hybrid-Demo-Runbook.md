# Azure Virtual Desktop Hybrid — MMS Demo Runbook

Companion to the session **"Azure Virtual Desktop Hybrid | Under The Hood: Features, Benefits, and the Fine Print"**
Presenters: Adam Nichols, Chris Cavazos · 5 demos · ~49 minutes of demo time inside a 60-75 minute slot

> AVD Hybrid is **not** AVD on Azure Local. There's no resource bridge, no custom location, no per-vCPU Azure Local fee, and no Session Host Configuration. Every session host here is a plain Azure Arc-enabled machine — a VM on whatever hypervisor you already run, or a physical server — registered to a host pool through the AVD Arc extension.

---

## 0. Lab build (do this before you travel)

Everything below assumes one lab subscription with a **host pool that has no session hosts in it**, plus a small number of machines you'll Arc-enable live. "On-premises" for demo purposes can be simulated with a Hyper-V VM on a laptop, a NUC you bring to the venue, or even a plain Azure VM sitting outside the host pool's usual fabric — Azure Arc doesn't care where the machine physically lives, only that it isn't already an Azure-managed AVD session host.

| Machine | Purpose | Notes |
|---|---|---|
| `hybrid-demo-01` | Live Arc-enable + registration in demo 3 | Windows 11 Enterprise or Windows Server, AD DS or hybrid-joined |
| `hybrid-demo-02` | Scripted registration in demo 4 | Same build as above; kept powered off until demo 4 |
| `hybrid-demo-03` (pre-staged) | Already registered and Available *before* the session starts | Backup so demo 5's connection test doesn't depend on demo 3/4 finishing live — registration can take up to 15 minutes after the extension succeeds |

**Required in the lab before the session**

- [ ] A **standard** host pool (pooled, single-session) with **no session hosts added through AVD** — Session Host Configuration is not an option for Hybrid pools, so there's nothing to configure there.
- [ ] A **workspace** and **application group**, with the app group added to the workspace.
- [ ] A **managed identity** (system- or user-assigned) attached to the host pool on the **Identity** tab.
- [ ] That managed identity granted **Reader** on the resource group containing your Arc-enabled machines — do this once, ahead of time, and again live in demo 3 for the narration.
- [ ] `Az.DesktopVirtualization` and `Az.ConnectedMachine` PowerShell modules installed on the demo machine, or Cloud Shell ready.
- [ ] `azcmagent` downloaded and tested on each demo machine (`azcmagent show`, `azcmagent check`).
- [ ] AD DS domain controller reachable from every demo machine, **or** confirm Windows 11 machines can go Microsoft Entra ID-only if you want to show that path (Windows Server cannot).
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

1. Azure portal → **Azure Virtual Desktop** → **Host pools** → create pool, type **Pooled**, management type **Standard** (there is no Session Host Configuration option to choose for Hybrid — say that explicitly).
2. On the **Identity** tab, assign a system-assigned or user-assigned **managed identity**. Call this out as the one step that's unique to Hybrid — this identity is what will read the Arc resource group later.
3. Continue through the wizard **without adding any virtual machines** — there is no "session hosts" step the way there is for a normal Azure-VM host pool.
4. Create the **workspace** and **application group**, add the app group to the workspace.
5. Open **Session hosts** on the new pool and show it empty. Say the sentence out loud: *"A Hybrid host pool is just a mailbox waiting for machines to register themselves — AVD doesn't create them."*
6. Switch tabs to **Azure Arc → Machines** and show the pre-staged demo machines sitting there, Arc-connected but not yet registered to any host pool. This sets up demo 3.

**Talk track:** contrast this with a normal AVD host pool, where the wizard lets you size, image, and create VMs right there. Hybrid deliberately has none of that — the machine's whole lifecycle already happened before AVD ever heard about it.

---

## Demo 2 — Pre-flight validation in five minutes (~8 min, after slide "Demo 2")

**Point to make:** there are two separate endpoint lists and one role assignment — almost every real failure traces back to one of these three things.

1. On `hybrid-demo-01`, run the Arc connectivity check:
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
   $hostPool    = Get-AzWvdHostPool -Name '<HostPoolName>' -ResourceGroupName '<HostPoolResourceGroup>'
   $principalId = $hostPool.IdentityPrincipalId
   New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Reader' -ResourceGroupName '<ArcServersResourceGroup>'
   ```
4. Confirm the machine's join type is compliant for its OS: Windows Server must be AD DS or hybrid-joined (never Entra-only); Windows 10/11 can be Entra ID-joined, AD DS-joined, or hybrid-joined.

**Talk track:** the two failures that eat the most time in the field are a missing Reader grant on the Arc resource group and confusing the AVD URL list with the Arc URL list. Both are checkable in under five minutes with what's on this slide.

---

## Demo 3 — Control plane, then the first session hosts (~12 min, after slide "Demo 3")

**Point to make:** this is the whole trick — Arc-enable, grant access, register, wait. Nothing here creates a VM.

1. If `hybrid-demo-01` isn't Arc-connected yet, connect it (skip on stage if it takes too long — narrate the command instead):
   ```powershell
   azcmagent connect --resource-group '<ResourceGroupName>' --subscription-id '<SubscriptionId>' --location '<Region>' --tenant-id '<TenantId>'
   ```
2. In **Azure Arc → Machines**, refresh and show the machine's status flip to **Connected**.
3. Generate a host pool registration token (valid for the window you choose — 24 hours is plenty for a demo):
   ```powershell
   $expiresUtc = (Get-Date).ToUniversalTime().AddHours(24).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
   $regInfo    = New-AzWvdRegistrationInfo -ResourceGroupName '<HostPoolResourceGroup>' -HostPoolName '<HostPoolName>' -ExpirationTime $expiresUtc
   $token      = $regInfo.Token
   ```
4. Install the **Azure Virtual Desktop Hybrid** extension on the Arc machine — do this in the portal for visibility: **Azure Arc → Machines → `hybrid-demo-01` → Extensions → Add → Azure Virtual Desktop Hybrid**, pick the subscription/resource group/host pool, **Review + Create**.
5. Flip to the **Extensions** blade and watch the status move to **Succeeded**. Say the token is single-use for this purpose and only lives in the protected settings.
6. Jump to the host pool's **Session hosts** blade and refresh. If `hybrid-demo-01` isn't **Available** yet (it can take up to 15 minutes), switch to the **pre-staged** `hybrid-demo-03` and show that one **Available** instead — be upfront that this is the same process, just further along.
7. Assign a test user to the application group and, if the pre-staged host is ready, connect once via Windows App to prove the loop closes.

**Talk track while it runs:** nothing here provisions or images a VM — AVD only starts caring once a machine with the extension installed asks to register. Compare this explicitly to slide "Deploy in this order, or rebuild": provision & Arc-enable, create the control plane, grant access & register, assign & validate.

**Leave `hybrid-demo-01`'s registration running.** Check back on it during demo 5's wrap-up.

---

## Demo 4 — Session hosts as code (~10 min, after slide "Demo 4")

**Point to make:** everything you just clicked through is four PowerShell cmdlets — this is what you'd actually put in a pipeline for the tenth machine, not the first.

```powershell
$rg        = 'rg-avdhybrid-demo'
$hostPool  = 'hp-avdhybrid-demo'
$machine   = 'hybrid-demo-02'
$location  = '<Azure Region>'

# 1. Confirm the machine is Arc-connected
Get-AzConnectedMachine -ResourceGroupName $rg -Name $machine | Select-Object Name, Status

# 2. Generate a registration token
$expiresUtc = (Get-Date).ToUniversalTime().AddHours(24).ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
$regInfo    = New-AzWvdRegistrationInfo -ResourceGroupName $rg -HostPoolName $hostPool -ExpirationTime $expiresUtc
$token      = $regInfo.Token

# 3. Install the AVD Arc extension, passing the token as a protected setting
$protectedSettings = @{ registrationToken = $token }
New-AzConnectedMachineExtension -Name 'Microsoft.AzureVirtualDesktop.CloudDeviceExtension' `
    -ResourceGroupName $rg -MachineName $machine -Location $location `
    -Publisher 'Microsoft.AzureVirtualDesktop' -ExtensionType 'CloudDeviceExtension' `
    -ProtectedSetting $protectedSettings

# 4. Validate the extension, then the host pool registration
Get-AzConnectedMachineExtension -ResourceGroupName $rg -MachineName $machine -Name 'Microsoft.AzureVirtualDesktop.CloudDeviceExtension'
Get-AzWvdSessionHost -ResourceGroupName $rg -HostPoolName $hostPool
```

**Say these three things while it runs**

- This is the exact call you'd wrap in a post-provisioning script, a Bicep deployment script resource, or a pipeline stage — Arc-enable the machine your way, then run these four cmdlets.
- The `Az.ConnectedMachine` and `Az.DesktopVirtualization` modules are both required; install them ahead of time, not live.
- Nothing about the machine's OS image, size, or disk is visible here — because AVD Hybrid never touched any of that. Your provisioning tool owns it entirely.
- Run this against a second and third machine and you've got your onboarding pipeline for the whole fleet.

---

## Demo 5 — Shortpath and the user experience (~9 min, after slide "Demo 5")

**Point to make:** AVD still brokers a desktop on an Arc-enabled machine. This lab uses **local profiles**; profile roaming is deliberately outside the demo.

1. Connect to the pre-staged, already-**Available** host from **Windows App**. A live user connection is the proof; the portal status alone is not.
2. Open the connection information flyout in the client and point out **RDP Shortpath** negotiated over UDP — call out that this works the same way it does for a cloud-hosted session host, direct across the LAN. If it negotiated TCP instead, show that honestly rather than claiming UDP.
3. Open `powershell.exe` in the session and run `hostname` and `whoami` to show the Arc-enabled host and the signed-in demo user. No network profile container is involved.
4. Disconnect and reconnect to the **same** Ready desktop to show the broker returns to that host and session. Do not narrate profile roaming across hosts; local desktop settings are scoped to that machine.
5. **Optional stretch demo:** block UDP 3390 at the host's firewall, reconnect, and show Shortpath fail to negotiate and fall back to RDP over TCP — a good "what does it look like when it's broken" moment if time allows.
6. Circle back to `hybrid-demo-01` from demo 3 — by now its registration should have finished. Refresh the **Session hosts** blade one more time and show it landed on its own, no extra clicks.

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
