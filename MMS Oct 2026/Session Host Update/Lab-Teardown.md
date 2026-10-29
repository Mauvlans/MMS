# Session Host Update lab — teardown record

**Completed:** 2026-10-29 UTC. The live lab is retired; the [runbook](Session-Host-Update-Demo-Runbook.md) and [demo scripts](demos/README.md) remain for reference only. No subscription or tenant IDs are recorded here.

## Deleted and verified

- The dedicated `rg-MMS-SessionHostUpdate` resource group: baseline inventory **50 ARM resources** (including seven AVD session-host VMs, two generalized image-source VMs, their disks/NICs, four tagged demo pools, gallery versions, workspace, Log Analytics, and Key Vault). The two additional empty, untagged AVD pool/application-group records in this same group were explicitly included by the owner. ARM GET for the group returned not found; a subscription-wide resource listing returned **zero resources** in the group and **zero resources** carrying the lab purpose tag elsewhere.
- Seven exact lab-created Microsoft Entra device objects corresponding to the seven session hosts: each was read by object ID and found absent after deletion. The four lab-pool managed-identity service principals were also read back absent.
- Eight exact role assignments belonging to the four lab-pool identities on the **shared** VNet and its AVD subnet: four VNet Reader and four subnet Network Contributor. Each role assignment was read back absent. The shared VNet and its four subnets remain present, and its two unrelated VNet role assignments remain untouched.

All seven session-host VMs were deallocated before the resource-group deletion. No shared VNet, subnet, other resource group, user account, or unrelated role assignment was deleted.

## Recoverable residue

Azure placed the lab Key Vault in **soft-deleted** state, with scheduled purge **2027-01-27 UTC**. It was **not forcibly purged**; its name may remain reserved until then. Soft-deleted service records are distinct from active billable VMs/disks/gallery replicas. Verify any other provider-specific recovery windows independently before attempting to reuse names.

Do not run the old lab power or update commands against this retired group. Rebuild a fresh isolated environment, supply its IDs privately, and rerun all readiness gates before another live presentation.
