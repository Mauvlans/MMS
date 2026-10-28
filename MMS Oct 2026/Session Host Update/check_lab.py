#!/usr/bin/env python3
"""Read-only MMS Session Host Update lab gate. Requires signed-in Azure CLI."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

SUB = os.environ.get("MMS_SUBSCRIPTION_ID", "").strip()
TENANT = os.environ.get("MMS_TENANT_ID", "").strip()
RG = "rg-MMS-SessionHostUpdate"
PREFIX = f"/subscriptions/{SUB}/resourceGroups/{RG}"
AVD = f"https://management.azure.com{PREFIX}/providers/Microsoft.DesktopVirtualization"
API = "2025-04-01-preview"
EXPECTED = {"hp-mms-demo": 4, "hp-mms-change": 1, "hp-mms-cli": 1, "hp-mms-history": 1}
LOGS = {"Checkpoint", "Error", "SessionHostManagement"}
QUERY_DIR = Path(__file__).with_name("demos")
QUERIES = {"successful updates": "05-success.kql", "failed update errors": "05-errors.kql"}


def az(*args: str) -> Any:
    result = subprocess.run(["az", *args, "-o", "json"], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:600])
    return json.loads(result.stdout)


def get(url: str) -> dict:
    return az("rest", "--method", "get", "--url", url)


def records(url: str) -> list[dict]:
    found = []
    while url:
        response = get(url)
        found += response.get("value", [])
        url = response.get("nextLink", "")
    return found


def gate(ok: bool, name: str, reason: str) -> bool:
    print(f"{'PASS' if ok else 'FAIL'} {name}: {reason}")
    return ok


def main() -> int:
    result = []
    guid = r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
    if not re.fullmatch(guid, SUB) or not re.fullmatch(guid, TENANT):
        raise RuntimeError("Set MMS_SUBSCRIPTION_ID and MMS_TENANT_ID to the intended lab GUIDs (not committed values).")
    account = az("account", "show")
    correct_account = (account.get("id", "").lower() == SUB.lower()
                       and account.get("tenantId", "").lower() == TENANT.lower())
    if not gate(correct_account, "subscription/tenant",
                "Azure context matches explicitly configured lab" if correct_account else "Azure context mismatch"):
        return 1
    for pool, expected in EXPECTED.items():
        base = f"{AVD}/hostPools/{pool}"
        host_pool = get(f"{base}?api-version={API}")
        result.append(gate(host_pool["properties"].get("managementType") == "Automated"
                           and host_pool["properties"].get("hostPoolType") == "Pooled",
                           pool + " type", str(host_pool["properties"].get("managementType"))))
        config = get(f"{base}/sessionHostConfigurations/default?api-version={API}")
        result.append(gate(config["properties"].get("provisioningState") == "Succeeded",
                           pool + " config", str(config["properties"].get("provisioningState"))))
        hosts = records(f"{base}/sessionHosts?api-version={API}")
        states = sorted((h["name"].split("/")[-1], h["properties"].get("status")) for h in hosts)
        result.append(gate(len(hosts) == expected and all(status == "Available" for _, status in states),
                           pool + " AVD hosts", f"{len(hosts)}/{expected}: {states}"))
        for h in hosts:
            vm_name = h["properties"].get("resourceId", "").split("/")[-1]
            statuses = az("vm", "get-instance-view", "--subscription", SUB,
                          "--resource-group", RG, "--name", vm_name,
                          "--query", "instanceView.statuses[].code")
            result.append(gate("PowerState/running" in statuses, vm_name + " power", str(statuses)))
        diagnostics = az("monitor", "diagnostic-settings", "list", "--resource", host_pool["id"])
        matching = [x for x in diagnostics if x["name"] == "diag-MMS-SessionHostUpdate"]
        enabled = {x["category"] for d in matching for x in d.get("logs", []) if x.get("enabled")}
        result.append(gate(LOGS <= enabled, pool + " diagnostics", str(sorted(enabled))))
    for version in ("1.0.0", "1.1.0"):
        image = az("sig", "image-version", "show", "--subscription", SUB,
                   "--resource-group", RG, "--gallery-name", "galMMSSessionHostUpdate",
                   "--gallery-image-definition", "Win11AVDTrusted",
                   "--gallery-image-version", version, "--expand", "ReplicationStatus")
        state = image.get("provisioningState")
        replicas = image.get("publishingProfile", {}).get("targetRegions", [{}])[0].get("regionalReplicaCount")
        replication = image.get("replicationStatus", {}).get("aggregatedState")
        result.append(gate(state == "Succeeded" and replicas == 2 and replication == "Completed",
                           "gallery " + version, f"{state}, {replicas} replicas, {replication}"))
    workspace = get(f"https://management.azure.com{PREFIX}/providers/Microsoft.OperationalInsights/"
                    "workspaces/law-MMS-SessionHostUpdate?api-version=2022-10-01")
    workspace_id = workspace["properties"]["customerId"]
    for label, filename in QUERIES.items():
        query = (QUERY_DIR / filename).read_text().strip()
        result.append(gate(bool(query), "Kusto query " + filename, f"{len(query)} characters"))
        if not query:
            continue
        url = f"https://api.loganalytics.io/v1/workspaces/{workspace_id}/query?" + urlencode({"query": query})
        try:
            data = az("rest", "--method", "get", "--resource", "https://api.loganalytics.io", "--url", url)
            count = len(data["tables"][0]["rows"])
            result.append(gate(count > 0, "Kusto " + label, f"{count} rows"))
        except (RuntimeError, KeyError, IndexError) as exc:
            result.append(gate(False, "Kusto " + label, str(exc)[:400]))
    print("MANUAL: stage-machine portal, signed-in user/notification, offline clips, timed rehearsal remain separate gates.")
    return 0 if all(result) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, KeyError, IndexError, subprocess.TimeoutExpired) as exc:
        print(f"FAIL probe aborted: {exc}", file=sys.stderr)
        sys.exit(2)
