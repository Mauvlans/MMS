#!/usr/bin/env python3
"""Power only the 7 MMS session hosts. Never starts generalized image-source VMs."""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import subprocess
import sys
import time
from typing import Any

SUB = "e6ab1306-dfc4-4975-9f15-1df30c4699e2"
RG = "rg-MMS-SessionHostUpdate"
EXPECTED = {"hp-mms-demo": 4, "hp-mms-change": 1, "hp-mms-cli": 1, "hp-mms-history": 1}
BASE = (f"https://management.azure.com/subscriptions/{SUB}/resourceGroups/{RG}"
        "/providers/Microsoft.DesktopVirtualization/hostPools")


def az(*args: str) -> Any:
    p = subprocess.run(["az", *args, "-o", "json"], capture_output=True, text=True, timeout=75)
    if p.returncode:
        raise RuntimeError(p.stderr.strip()[:600])
    return json.loads(p.stdout)


def hosts() -> list[dict]:
    if az("account", "show")["id"] != SUB:
        raise RuntimeError("Wrong Azure subscription. Refusing power operation.")
    found = []
    for pool, count in EXPECTED.items():
        url = f"{BASE}/{pool}/sessionHosts?api-version=2025-04-01-preview"
        items = []
        while url:
            response = az("rest", "--url", url)
            items.extend(response.get("value", []))
            url = response.get("nextLink", "")
        if len(items) != count:
            raise RuntimeError(f"{pool}: expected {count} AVD hosts, found {len(items)}. Refusing.")
        for item in items:
            vm_id = item["properties"].get("resourceId", "")
            if not vm_id.lower().startswith(
                    f"/subscriptions/{SUB}/resourcegroups/{RG}/providers/microsoft.compute/virtualmachines/".lower()):
                raise RuntimeError(f"{pool}: VM outside isolated lab RG: {vm_id}")
            vm = az("vm", "show", "--ids", vm_id)
            if vm.get("tags", {}).get("pool") != pool or vm.get("tags", {}).get("purpose") != "MMS-SessionHostUpdate":
                raise RuntimeError(f"{pool}: VM ownership tags mismatch: {vm_id}")
            found.append({"pool": pool, "name": item["name"], "vm_id": vm_id,
                          "active": item["properties"].get("activeSessions", 0),
                          "disconnected": item["properties"].get("disconnectedSessions", 0)})
    if len(found) != sum(EXPECTED.values()) or len({x["vm_id"].lower() for x in found}) != len(found):
        raise RuntimeError("Unexpected host inventory or duplicate VM IDs. Refusing.")
    return found


def vm_state(vm_id: str) -> str:
    details = az("vm", "get-instance-view", "--ids", vm_id)
    statuses = [x["code"] for x in details.get("instanceView", {}).get("statuses", [])]
    return next((x for x in statuses if x.startswith("PowerState/")), str(statuses))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "start", "deallocate"))
    args = parser.parse_args()
    inventory = hosts()
    print("Scoped AVD hosts:", len(inventory), "in", RG, flush=True)
    if args.action == "deallocate" and any(x["active"] or x["disconnected"] for x in inventory):
        raise RuntimeError("At least one user session exists. Refusing deallocation.")
    if args.action != "status":
        verb = "start" if args.action == "start" else "deallocate"
        def change(item: dict) -> tuple[str, str]:
            az("vm", verb, "--ids", item["vm_id"], "--no-wait")
            return item["name"], "requested"
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as workers:
            for name, outcome in workers.map(change, inventory):
                print(verb, name, outcome, flush=True)
    target = "PowerState/running" if args.action == "start" else "PowerState/deallocated"
    for attempt in range(50 if args.action != "status" else 1):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as workers:
            states = list(workers.map(vm_state, (x["vm_id"] for x in inventory)))
        pending = [(x["name"], state) for x, state in zip(inventory, states) if state != target]
        print(f"{target}: {len(inventory) - len(pending)}/{len(inventory)}; pending={pending}", flush=True)
        if not pending:
            if args.action == "start":
                print("Power is running. Now run check_lab.py and wait for every AVD host to become Available.")
            return 0
        if args.action == "status":
            return 1
        time.sleep(12)
    raise RuntimeError(f"Timed out waiting for {target}; inspect the exact pending VMs above.")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, KeyError, subprocess.TimeoutExpired) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(2)
