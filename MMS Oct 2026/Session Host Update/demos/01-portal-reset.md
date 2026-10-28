# Demo 1 — Schedule an update from the Azure portal (~8 min, after slide "Demo 1")

[← Session runbook](../Session-Host-Update-Demo-Runbook.md) · Portal presenter script

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
