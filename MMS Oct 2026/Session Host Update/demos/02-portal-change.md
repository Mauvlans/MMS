# Demo 2 — Change image, VM size and disk type (~10 min, after slide "Demo 2")

[← Session runbook](../Session-Host-Update-Demo-Runbook.md) · Portal presenter script

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
