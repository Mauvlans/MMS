# Demo 4 — Monitor, pause, resume, cancel (~10 min, after slide "Demo 4")

[← Session runbook](../Session-Host-Update-Demo-Runbook.md) · Portal presenter script

**Point to make:** you are never locked in mid-update, but cancel has a real cost.

1. Return to `hp-mms-demo` → **Session hosts**. Check whether the update from demo 1 is past the initial host; do not promise this by the demo-4 slot.
2. Show the **blue banner**, select **Refresh** and read the progress. Point at the host list: replaced hosts carry the `SessionHostName-DateTime` naming on their Azure resources while the **OS host name is unchanged**.
3. If an update is actively running and time permits, select **Manage session host update** → **Pause**. The banner may refresh after ~20 seconds, but the pause **does not complete until the batch in flight finishes**. Use the pre-recorded pause result if the batch is still running.
4. **Only after status reads Paused**, select **Resume** and show it continuing; otherwise play the recorded resume result. Mention: an update left paused for **two weeks is cancelled automatically**.
5. Show the **Cancel** and **Retry** buttons without pressing Cancel on the good pool. Give the warning verbatim: a cancelled update **cannot be resumed**, and a pool cancelled mid-flight can end up with **mixed OS versions or mixed domains** — schedule a replacement update immediately.
6. Switch to the separate `hp-mms-history` pool and show its **failed** update and **Retry** path only if that state was pre-staged and is safe to retry; otherwise use the recorded failure/retry clip. A *cancelled* update cannot be resumed. Note that a host pool with a failed update **cannot be deleted until the update is cancelled**.
7. Two rules to repeat: **do not remove VMs from the pool** and **do not touch drain mode** while an update is running — the service owns drain mode for the duration and resets it at the end.
8. Optional 30-second detour: **Azure Monitor → Activity log** filtered to the host pool, showing the same operations from the ARM side.
