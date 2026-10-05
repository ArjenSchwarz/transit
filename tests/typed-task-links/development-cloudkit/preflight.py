"""Reserved development smoke preflight. Default validates only; --run launches.

Future task2-only invocation after operator setup and parent environment/slot clearance:
  python3 tests/typed-task-links/development-cloudkit/preflight.py \
    RESERVED_SMOKE.app REVIEWED_CONTRACT.json EXACT_REVIEWED_SHA256

Append --run only when external execution is cleared. Never uses Transit.app.
No compilation, signing changes, schema initialization or production promotion.
"""

import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import uuid


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("contract", type=pathlib.Path)
    parser.add_argument("sha256")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    app = args.app.resolve()
    raw = args.contract.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == args.sha256, "Reviewed contract hash mismatch")
    contract = json.loads(raw)
    require(contract["reservedDevelopmentEnvironment"] is True, "Reserved development contract required")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    identity = "me.nore.ig.Transit.development.cloudkit-smoke"
    require(info["CFBundleIdentifier"] == identity, "Dedicated smoke-host identity required")
    require(info["CFBundleExecutable"] == "TaskLinkDevelopmentSmoke", "Dedicated executable required")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(app)], check=True)
    signature = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)],
                               capture_output=True, check=True)
    entitlements = plistlib.loads(signature.stdout)
    require(entitlements.get("com.apple.developer.icloud-container-environment") == "Development",
            "Production CloudKit environment forbidden")
    require(entitlements.get("com.apple.developer.icloud-container-identifiers") == [contract["containerID"]],
            "Exactly the reserved contract container required")
    require(entitlements.get("com.apple.developer.icloud-services") == ["CloudKit"], "Only CloudKit service allowed")
    require(entitlements.get("com.apple.security.get-task-allow") is True, "Development signing required")
    require(entitlements.get("com.apple.security.app-sandbox") is True, "Dedicated sandbox required")
    require(not any("aps-environment" in key or "application-groups" in key for key in entitlements),
            "Push/app-group entitlements forbidden")
    root = pathlib.Path.home() / "Library/Containers" / identity / "Data/tmp" / ("T1734Dev-" + str(uuid.uuid4()))
    require(not root.exists() and not root.is_symlink(), "Fresh synthetic root required")
    evidence = dict(host=str(app), contractSHA256=args.sha256, root=str(root),
                    cloudEnvironment="Development", container=contract["containerID"], launched=args.run)
    print(json.dumps(evidence, indent=2), flush=True)
    if args.run:
        environment = dict(os.environ, T1734_DEV_SMOKE_CLEARED="1")
        require(root.parent.is_dir() and root.parent.resolve() == root.parent,
                "Provisioned canonical smoke-host private tmp required")
        private_contract = root.parent / ("T1734Contract-" + str(uuid.uuid4()) + ".json")
        with private_contract.open("xb") as stream:
            stream.write(raw)  # Exact reviewed bytes, readable in the smoke sandbox.
        child = subprocess.Popen([str(app / "Contents/MacOS/TaskLinkDevelopmentSmoke"),
                                  str(private_contract), str(root)], env=environment)
        try:
            exit_code = child.wait(timeout=180)
        except subprocess.TimeoutExpired:
            sample_path = root.parent / ("T1734Timeout-" + str(uuid.uuid4()) + ".sample.txt")
            sample_evidence = dict(pid=child.pid, output=str(sample_path))
            try:
                sample = subprocess.run(["/usr/bin/sample", str(child.pid), "2", "10",
                                         "-file", str(sample_path)],
                                        capture_output=True, text=True, timeout=8, check=False)
                sample_evidence.update(exitCode=sample.returncode, stdout=sample.stdout, stderr=sample.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                sample_evidence["error"] = str(error)
            try:
                with sample_path.with_suffix(".json").open("x") as stream:
                    stream.write(json.dumps(sample_evidence, indent=2) + "\n")
            except OSError as error:
                sample_evidence["evidenceWriteError"] = str(error)
            print(json.dumps(dict(timeoutSample=sample_evidence), indent=2), flush=True)
            # Only the exact child launched here; never another app or host.
            child.terminate()
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=5)
            raise RuntimeError(f"Smoke deadline exceeded; owned PID {child.pid} terminated")
        inspection = subprocess.run(["/bin/ps", "-p", str(child.pid), "-o", "pid=,command="],
                                    capture_output=True, text=True)
        require(inspection.returncode == 1 and not inspection.stdout.strip() and not inspection.stderr.strip(),
                "Owned PID drain not proved; stop for parent inspection")
        require(exit_code == 0, f"Smoke failed with exit {exit_code}; retained fixture evidence")


if __name__ == "__main__":
    main()
