# Session Host Update — stage index

> **Retired lab:** the October 2026 Azure lab was torn down. These are historical presenter scripts, not a runnable environment. [Teardown record](../Lab-Teardown.md). Rebuild and revalidate an isolated lab before executing any update or power action.

[Common lab preparation, safety gates, and timing](../Session-Host-Update-Demo-Runbook.md). For any **newly rebuilt** lab, use the guarded `lab_power.py` only after verifying ownership and host counts, then run `check_lab.py` before presenting; **never start generalized image-source VMs**. The common prep is not repeated in each cue card.

1. [Demo 1 — portal update](01-portal-reset.md): start the four-host `hp-mms-demo` update.
2. [Demo 2 — portal image, size, and disk](02-portal-change.md): use independent `hp-mms-change`.
3. [Demo 3 — PowerShell update](03-powershell-update.md): presenter cues and [guarded `03-update.ps1`](03-update.ps1) for independent `hp-mms-cli`. Default `Check` reads only; `-Action Run` changes the pool after confirmation; `-WhatIf` is an offline preview, not a cloud readiness check.
4. [Demo 4 — monitor, pause, and resume](04-monitor-control.md): return to the **Demo 1 update**; use a verified recording when live timing does not align.
5. [Demo 5 — diagnostics](05-diagnostics.md): open [success](05-success.kql) and [failure](05-errors.kql) queries in separate Log Analytics tabs. A live failure is **not** proven until the failure query returns a real row.

Portal demos use individual **presenter scripts** (`.md`), not executable portal automation. The PowerShell script and Kusto queries are separate copy/run artifacts. Do not start a second update on a pool with one already scheduled or running.
