"""Prepare exactly one opt-in primitive diagnostic; no launch without --run.

After the parent's guarded shared Transit Debug build and control run:
  python3 tests/typed-task-links/run_commit_diagnostic.py BUILD_PRODUCTS

Add --run in the assigned exclusive slot. Use fresh diagnostic outputs; a prior
preparation reserves them, so execution uses a fresh products copy/build.
The default single case documents a counterexample, never graph atomicity.
Use --diagnostic internal-save-abort for the internal-flush abort prerequisite;
its pass establishes abort durability only, not peer exclusion or atomicity.
"""

import argparse
import json
import os
import pathlib
import plistlib
import signal
import subprocess
import time

from prepare_unit_run import require, validated_unit_run


IDENTIFIER = "TaskLinkCommitBoundaryTests/primitiveTransactionEarlierObservationCanBeInvalidatedByPeerSave()"
DIAGNOSTICS = {
    "read-first-peer": (IDENTIFIER, "T1734_TRANSACTION_DIAGNOSTIC"),
    "internal-save-abort": (
        "TaskLinkCommitBoundaryTests/primitiveTransactionInternalSaveMustRollBackOnClosureAbort()",
        "T1734_TRANSACTION_ABORT_DIAGNOSTIC"),
}


def processes():
    result = subprocess.run(["/bin/ps", "-axww", "-o", "pid=,ppid=,command="],
                            capture_output=True, text=True, check=True, timeout=5)
    require(not result.stderr.strip(), "Process inspection diagnostic; stop without termination")
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(maxsplit=2)
        require(len(parts) == 3, "Incomplete process inspection; stop")
        rows[int(parts[0])] = (int(parts[1]), parts[2])
    require(os.getpid() in rows, "Process inspection unavailable; stop")
    return rows


def host_processes(rows, executables, bundles):
    hosts = {}
    for pid, (_, command) in rows.items():
        if any(command == path or command.startswith(path + " ") for path in executables):
            hosts[pid] = command
        elif any(path in command for path in bundles):
            raise RuntimeError(f"Test-bundle process attribution unavailable, PID {pid}; retain for parent inspection")
    return hosts


def stop_owned(pid, expected, products, reap=None):
    rows = processes()
    if pid not in rows:
        return
    require(rows[pid][1] == expected, f"PID {pid} identity changed; no signal sent")
    sample = products / ("T1734Diagnostic-timeout-" + str(pid) + ".sample.txt")
    require(not sample.exists(), "Fresh trace required")
    try:
        captured = subprocess.run(["/usr/bin/sample", str(pid), "2", "10", "-file", str(sample)],
                                  capture_output=True, text=True, timeout=8, check=False)
        evidence = dict(pid=pid, command=expected, exitCode=captured.returncode,
                        stdout=captured.stdout, stderr=captured.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        evidence = dict(pid=pid, command=expected, error=str(error))
    try:
        with sample.with_suffix(".json").open("x") as stream:
            stream.write(json.dumps(evidence, indent=2) + "\n")
    except OSError as error:
        print(json.dumps(dict(sampleEvidence=evidence, evidenceWriteError=str(error))), flush=True)
    for action, seconds in ((signal.SIGTERM, 5), (signal.SIGKILL, 3)):
        rows = processes()
        if pid not in rows:
            return
        require(rows[pid][1] == expected, f"PID {pid} changed after sampling; no signal sent")
        os.kill(pid, action)
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if reap is not None:
                reap()
            if pid not in processes():
                return
            time.sleep(0.1)
    require(pid not in processes(), f"Owned PID {pid} not drained; parent inspection required")


def stop_known_child(child, traces):
    """Popen proves child ownership even when host/process inspection fails."""
    if child.poll() is not None:
        return
    sample = traces / "inspection-failure-child.sample.txt"
    captured = dict(pid=child.pid, hostDrainProved=False)
    try:
        result = subprocess.run(["/usr/bin/sample", str(child.pid), "2", "10", "-file", str(sample)],
                                capture_output=True, text=True, timeout=8, check=False)
        captured.update(exitCode=result.returncode, stdout=result.stdout, stderr=result.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        captured["error"] = str(error)
    try:
        with sample.with_suffix(".json").open("x") as stream:
            stream.write(json.dumps(captured, indent=2) + "\n")
    except OSError as error:
        print(json.dumps(dict(sampleEvidence=captured, evidenceWriteError=str(error))), flush=True)
    child.terminate()
    try:
        child.wait(timeout=5)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("products", type=pathlib.Path)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--diagnostic", choices=DIAGNOSTICS, default="read-first-peer")
    args = parser.parse_args()
    identifier, environment_flag = DIAGNOSTICS[args.diagnostic]
    original = args.products.absolute()
    products = args.products.resolve()
    derived = products / "T1734CommitDiagnostic.xctestrun"
    result = products / "T1734CommitDiagnostic.xcresult"
    evidence_path = products / "t1734-commit-diagnostic-preflight.json"
    log_path = products / "t1734-commit-diagnostic.log"
    result_json = products / "t1734-commit-diagnostic-result.json"
    summary_path = products / "t1734-commit-diagnostic-summary.json"
    tree_path = products / "t1734-commit-diagnostic-tests.json"
    traces = products / "T1734CommitDiagnostic-traces"
    for output in (derived, result, evidence_path, log_path, result_json, summary_path, tree_path, traces):
        require(not output.exists() and not output.is_symlink(), f"Fresh output required: {output}")
    configuration, unit, host, info, entitlements, source = validated_unit_run(products)
    unit["OnlyTestIdentifiers"] = [identifier]
    for _, flag in DIAGNOSTICS.values():
        unit["EnvironmentVariables"].pop(flag, None)
    unit["EnvironmentVariables"][environment_flag] = "1"
    roots = {str(original), str(products), str(products).removeprefix("/private")}
    executables = {root + "/Debug/Transit.app/Contents/MacOS/Transit" for root in roots}
    bundles = {root + "/Debug/TransitTests.xctest" for root in roots}
    require(not host_processes(processes(), executables, bundles), "Existing build host; no launch allowed")
    with derived.open("xb") as stream:
        plistlib.dump(configuration, stream)
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(derived),
               "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
               "-only-testing:TransitTests/" + identifier, "-resultBundlePath", str(result)]
    evidence = dict(host=str(host), bundleID=info["CFBundleIdentifier"], entitlements=entitlements,
                    sourceXctestrun=str(source), command=command, launched=args.run,
                    timeoutSeconds=60, expectedCases=1, diagnostic=args.diagnostic, atomicityProof=False)
    with evidence_path.open("x") as stream:
        stream.write(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2), flush=True)
    if not args.run:
        return
    traces.mkdir()
    with log_path.open("x") as log:
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            owned = {}
            deadline = time.monotonic() + 60
            while child.poll() is None and time.monotonic() < deadline:
                owned.update(host_processes(processes(), executables, bundles))
                time.sleep(0.25)
            timed_out = child.poll() is None
            drain_deadline = time.monotonic() + 5
            while time.monotonic() < drain_deadline:
                live_hosts = host_processes(processes(), executables, bundles)
                owned.update(live_hosts)
                if not live_hosts and child.poll() is not None:
                    break
                time.sleep(0.1)
            live = processes()
            stalled = {pid: command_line for pid, command_line in owned.items() if pid in live}
            if timed_out or stalled:
                # Exact signed host paths, absent before launch and observed during
                # this run. Never kill another build, a process group or user app.
                for pid, command_line in stalled.items():
                    stop_owned(pid, command_line, traces)
                if child.poll() is None:
                    row = processes().get(child.pid)
                    require(row is not None and row[0] == os.getpid()
                            and pathlib.Path(row[1].split(maxsplit=1)[0]).name == "xcodebuild"
                            and str(derived) in row[1] and "-xctestrun" in row[1],
                            "Owned xcodebuild command unavailable; stop for parent inspection")
                    stop_owned(child.pid, row[1], traces, reap=child.poll)
                    child.wait(timeout=5)
                raise RuntimeError("Diagnostic timeout/teardown stall; traces retained, no atomicity proof")
            require(not host_processes(processes(), executables, bundles), "Host drain not established")
            require(not any(pid in processes() for pid in owned), "Recorded host PID drain not established")
            summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                                     capture_output=True, text=True, check=True, timeout=15)
            with summary_path.open("x") as stream:
                stream.write(summary.stdout)
            tree_result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests",
                                          "--path", str(result)],
                                         capture_output=True, text=True, check=True, timeout=15)
            with tree_path.open("x") as stream:
                stream.write(tree_result.stdout)
            tree = json.loads(tree_result.stdout)
            nodes = list(tree["testNodes"])
            cases = []
            while nodes:
                node = nodes.pop()
                nodes.extend(node.get("children", []))
                if node.get("nodeType") == "Test Case":
                    cases.append(node)
            require(len(cases) == 1 and cases[0].get("nodeIdentifier") == identifier,
                    "Exact diagnostic case not executed; inspect retained tree")
            counts = json.loads(summary.stdout)
            require(counts.get("totalTestCount") == 1 and counts.get("skippedTests") == 0,
                    "Exactly one executed diagnostic required; inspect discovery/result failure")
            if (args.diagnostic == "internal-save-abort" and child.returncode == 65
                    and counts.get("failedTests") == 1 and counts.get("passedTests") == 0
                    and cases[0].get("result") == "Failed"):
                with result_json.open("x") as stream:
                    stream.write(json.dumps(dict(summary=counts, hostDrained=True, diagnostic=args.diagnostic,
                                                 abortDurabilityObserved=False, exactCaseFailed=True,
                                                 atomicityProof=False), indent=2) + "\n")
                raise RuntimeError("Abort prerequisite failed; inspect exact issues before candidate disposition")
            require(cases[0].get("result") == "Passed", "Diagnostic case not passed; inspect retained tree")
            require(child.returncode == 0 and counts.get("passedTests") == 1 and counts.get("failedTests") == 0,
                    "Diagnostic failed; inspect retained result, no atomicity proof")
            with result_json.open("x") as stream:
                stream.write(json.dumps(dict(summary=counts, hostDrained=True, diagnostic=args.diagnostic,
                                             counterexampleObserved=args.diagnostic == "read-first-peer",
                                             abortDurabilityObserved=args.diagnostic == "internal-save-abort",
                                             atomicityProof=False), indent=2) + "\n")
        finally:
            stop_known_child(child, traces)


if __name__ == "__main__":
    main()
