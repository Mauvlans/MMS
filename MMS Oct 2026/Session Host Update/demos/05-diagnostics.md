# Demo 5 — Prove it with Kusto (~8 min, after slide "Demo 5")

[← Session runbook](../Session-Host-Update-Demo-Runbook.md) · Presenter script

**Point to make:** "did it work, how long did it take, and what broke" are all queryable.

Open **Log Analytics** on the workspace attached to `hp-mms-history`. Have both queries **pre-pasted in tabs** — do not type Kusto on stage.

**Measured lab state:** the isolated `hp-mms-history` pool completed a real `1.0.0 → 1.1.0` update (the replacement host read back **Available**, **Microsoft Entra joined**, and its on-disk marker says `1.1.0`). Query A produced one real result after log ingestion. **Query B currently has zero rows**: no failed *update* has been staged, so this portion is **not live-ready**. Stage a failure safely in this dedicated pool and rerun the exact query, or capture a verified failure recording before claiming Demo 5 is ready. Do not present an unrelated configuration-validation failure as an update failure.

**Query A — successful updates, duration and median minutes per host (last 30 days)**

**Copy/run:** [05-success.kql](05-success.kql)

Land the point on **MedianSessionHostUpdateTime** and **UpdateBatchSize** together: that pair is how you size the next maintenance window instead of guessing.

**Query B — errors during updates (last 30 days)**

**Copy/run:** [05-errors.kql](05-errors.kql)

Show a real `CodeSymbolic` from your lab **only if Query B returned a row**; otherwise play the verified failure recording. If you actually have `AgentRegistrationFailureGeneric`, it illustrates an intermittent large-batch failure that retrying often clears. Do not invent or promise that specific code.

**Close the demo block by naming the fix for the classic failure:** if the source image was captured from a running session host, delete `C:\packages\plugin` before capturing — that folder blocks the DSC extension that joins updated VMs to the host pool.
