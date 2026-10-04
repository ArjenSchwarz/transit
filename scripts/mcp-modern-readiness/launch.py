#!/usr/bin/env python3
"""Run a reviewed signed-unit fixture packet; never production Transit or clients."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import os
import signal
import subprocess
import time
from verify import verify


def bounded_cleanup(packet, host, directory):
    """Timeout diagnostics precede identity-scoped runner-first termination."""
    def owned(marker, executable):
        rows = subprocess.check_output(["ps", "-axo", "pid=,comm=,args="], text=True).splitlines()
        matches = []
        for row in rows:
            parts = row.strip().split(None, 2)
            if len(parts) == 3 and parts[1].endswith(executable) and marker in parts[2]:
                matches.append(int(parts[0]))
        if len(matches) > 1:
            raise RuntimeError("Cannot establish unique owned timeout identity: " + marker)
        return matches[0] if matches else None
    plist = re.search(r"-xctestrun (\S+)", packet["test"])[1]
    runner = owned(plist, "xcodebuild")
    guarded_host = owned(host, "/Transit")
    proof = []
    for label, pid in (("runner", runner), ("host", guarded_host)):
        if pid is None:
            proof.append({"identity": label, "state": "already absent", "sample": None})
            continue
        subprocess.run(["sample", str(pid), "3", "1", "-file", str(directory / (label + "-sample.txt"))], check=True)
        proof.append({"identity": label, "pid": pid, "sampleExit": 0})
    (directory / "timeout-identities-and-samples.json").write_text(json.dumps(proof, indent=2))
    for pid, marker in ((runner, plist), (guarded_host, host)):
        if pid is None:
            continue
        identity = subprocess.run(["ps", "-p", str(pid), "-o", "args="], capture_output=True, text=True)
        if identity.returncode:
            continue
        if marker not in identity.stdout:
            raise RuntimeError("Owned timeout identity changed")
        os.kill(pid, signal.SIGTERM)
        for _ in range(40):
            if subprocess.run(["ps", "-p", str(pid)], capture_output=True).returncode:
                break
            time.sleep(.25)
        else:
            raise RuntimeError("Owned timeout process did not drain")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--packet", required=True)
    parser.add_argument("--packet-sha256", required=True)
    parser.add_argument("--hold-seconds", type=int, default=0)
    args = parser.parse_args()
    if not 0 <= args.hold_seconds <= 120:
        raise ValueError("Isolated hold must be between zero and 120 seconds")
    path = pathlib.Path(args.packet).resolve()
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != args.packet_sha256:
        raise ValueError("Reviewed packet hash changed")
    packet = json.loads(raw)
    if set(packet["expectedTestDeclarations"]) != {"MCPModernReadinessTests"}:
        raise ValueError("Launcher requires only the isolated readiness fixture suite")
    cwd = pathlib.Path(packet["cwd"])
    outputs = []
    for key in ("build", "preflight", "enumerate", "test"):
        command = packet[key]
        for pattern in (r"> (\S+)", r"-resultBundlePath (\S+)", r"-test-enumeration-output-path (\S+)"):
            match = re.search(pattern, command)
            if match:
                output = pathlib.Path(match[1])
                outputs.append(output if output.is_absolute() else cwd / output)
    match = re.search(r"-xctestrun (\S+)", packet["test"])
    outputs.append(pathlib.Path(match[1]))
    outputs.extend(path.parent / name for name in ("actual-readiness-trace.json", "timeout-identities-and-samples.json", "stage-results.json"))
    if any(output.exists() for output in outputs):
        raise ValueError("Fresh packet outputs required; prior evidence must never be overwritten")
    stages = {}
    stage_path = path.parent / "stage-results.json"
    for key in ("sourceReady", "setup", "build", "preflight", "enumerate", "inventoryCheck"):
        result = subprocess.run(packet[key], shell=True, cwd=packet["cwd"])
        stages[key] = result.returncode
        stage_path.write_text(json.dumps(stages, indent=2))
        print(json.dumps({"stage": key, "actualExit": result.returncode}), flush=True)
        if result.returncode:
            raise subprocess.CalledProcessError(result.returncode, packet[key])
    # A hold is unit-target-only; persistence/smoke/host guards remain mandatory.
    match = re.search(r"-xctestrun (\S+)", packet["test"])
    plist_path = pathlib.Path(match[1])
    configuration = plistlib.loads(plist_path.read_bytes())
    targets = configuration["TestConfigurations"][0]["TestTargets"]
    if len(targets) != 1 or targets[0]["BlueprintName"] != "TransitTests":
        raise ValueError("Only inspected unit target is eligible")
    environment = targets[0]["EnvironmentVariables"]
    if environment.get("TRANSIT_PERSISTENCE_MODE") != "unit-test" or environment.get("TRANSIT_ISOLATION_SMOKE") != "1":
        raise ValueError("Isolation guards missing")
    environment["TRANSIT_READINESS_HOLD_SECONDS"] = str(args.hold_seconds)
    plist_path.write_bytes(plistlib.dumps(configuration))
    log = pathlib.Path(packet["cwd"]) / re.search(r"> (\S+) 2>&1", packet["test"])[1]
    print(json.dumps({"testLog": str(log), "boundedHoldSeconds": args.hold_seconds,
                      "clientActivation": False}), flush=True)
    process = subprocess.Popen(packet["test"], shell=True, cwd=packet["cwd"])
    advertised = False
    cutoff = time.monotonic() + args.hold_seconds + 180
    while process.poll() is None:
        if log.exists() and not advertised:
            match = re.search(r"T2383_MODERN_READINESS_ENDPOINT=(.+)", log.read_text())
            if match:
                print(pathlib.Path(match[1]).read_text(), flush=True)
                advertised = True
        if time.monotonic() >= cutoff:
            bounded_cleanup(packet, environment["TRANSIT_SMOKE_HOST_PATH"], path.parent)
            process.wait(timeout=10)
            raise RuntimeError("Fixture exceeded bounded runtime; diagnostics preserved, no proof accepted")
        time.sleep(.25)
    stages["test"] = process.returncode
    stage_path.write_text(json.dumps(stages, indent=2))
    if process.returncode:
        raise RuntimeError("Actual app fixture failed; no negotiation evidence accepted")
    match = re.search(r"T2383_MODERN_READINESS_EXPORT=(.+)", log.read_text())
    if not match:
        raise ValueError("Actual app export absent")
    source = pathlib.Path(match[1])
    destination = path.parent / "actual-readiness-trace.json"
    shutil.copyfile(source, destination)
    print(json.dumps(verify(json.loads(destination.read_text())), sort_keys=True))


if __name__ == "__main__":
    main()
