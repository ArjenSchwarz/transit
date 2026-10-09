"""Prepare four isolated runs; launch ONLY with --run in the parent's heavy slot.

After a fresh shared Transit Debug build-for-testing (see prepare_unit_run.py):
  python3 tests/typed-task-links/run_closed_store.py BUILD_PRODUCTS

For execution, use another fresh build directory and append --run. This always
invokes the existing signed-host preflight first, never bypassing its checks.
Runs seed -> legacy reopen -> current-schema upgrade -> current-schema reopen.
No cleanup deletes stores. Original SQLite/WAL/SHM and JSON evidence remain in
the development app's private Data/tmp directory for inspection after drain.
"""

import argparse
import copy
import json
import pathlib
import plistlib
import sqlite3
import subprocess
import sys
import time
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "typed-task-links"))
from prepare_unit_run import require, validated_unit_run


def drained(products, stage_pid=None):
    """Inspect only this build's host/test processes; never terminate anything."""
    deadline = time.monotonic() + 15
    while True:
        inspection = subprocess.run(["/bin/ps", "-axo", "pid=,command="],
                                    capture_output=True, text=True, check=True)
        roots = {str(products), str(products).removeprefix("/private")}
        paths = [root + suffix for root in roots for suffix in
                 ("/Debug/TransitDevelopment.app/Contents/MacOS/TransitDevelopment", "/Debug/TransitTests.xctest")]
        owned = [line for line in inspection.stdout.splitlines()
                 if any(path in line for path in paths)
                 or (stage_pid is not None and line.strip().split(maxsplit=1)[0] == str(stage_pid))]
        if not owned:
            return
        require(time.monotonic() < deadline, f"Owned processes not drained; parent inspection required: {owned}")
        time.sleep(0.25)


def graph_rows(root):
    """Read-only physical counts, not graph projection or CloudKit evidence."""
    store = root / "pre-feature.store"
    with sqlite3.connect(store.as_uri() + "?mode=ro", uri=True) as connection:
        tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        counts = {}
        for entity in ("TaskConsolidationEvent",):
            matches = [name for name in tables if name.upper() == "Z" + entity.upper()]
            require(len(matches) == 1, f"Unrecognized SQLite schema for {entity}: {sorted(tables)}")
            name = matches[0]  # Allowlisted entity name above; no external SQL identifier.
            counts[entity] = connection.execute('SELECT COUNT(*) FROM "' + name + '"').fetchone()[0]
        require(all(count == 0 for count in counts.values()), f"New consolidation history rows are not empty: {counts}")
        return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("products", type=pathlib.Path)
    parser.add_argument("--run", action="store_true", help="Explicitly launch after parent slot release")
    args = parser.parse_args()
    products = args.products.resolve()
    base, _, _, _, _, _ = validated_unit_run(products)
    token = str(uuid.uuid4()).upper()
    root = (pathlib.Path.home() / "Library/Containers/me.nore.ig.Transit.development/Data/tmp"
            / ("T2381Closed-" + token))
    require(not root.exists(), f"Fresh synthetic fixture root required: {root}")
    runs = []
    for stage in ("seed", "legacy", "upgrade", "reopen"):
        configuration = copy.deepcopy(base)
        if "TestConfigurations" in configuration:
            targets = [target for item in configuration["TestConfigurations"] for target in item["TestTargets"]]
        else:
            targets = [value for key, value in configuration.items()
                       if not key.startswith("__") and isinstance(value, dict)]
        require(len(targets) == 1 and targets[0]["BlueprintName"] == "TransitTests", "Unit-only base required")
        unit = targets[0]
        unit["OnlyTestIdentifiers"] = ["TaskConsolidationMigrationTests"]
        unit["EnvironmentVariables"].update(T2381_CLOSED_STAGE=stage, T2381_CLOSED_TOKEN=token)
        derived = products / ("T2381Closed-" + stage + ".xctestrun")
        result = products / ("T2381Closed-" + stage + ".xcresult")
        require(not result.exists(), f"Fresh result required: {result}")
        with derived.open("xb") as stream:
            plistlib.dump(configuration, stream)
        command = ["xcodebuild", "test-without-building", "-xctestrun", str(derived),
                   "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
                   "-only-testing:TransitTests/TaskConsolidationMigrationTests",
                   "-resultBundlePath", str(result)]
        runs.append(dict(stage=stage, command=command, result=str(result)))
    plan = dict(token=token, root=str(root), runs=runs, expectedCasesPerStage=1,
                cloudKit="none", launched=args.run)
    with (products / "t2381-closed-plan.json").open("x") as stream:
        stream.write(json.dumps(plan, indent=2) + "\n")
    print(json.dumps(plan, indent=2), flush=True)
    if not args.run:
        return
    prior_pids = set()
    for run in runs:
        drained(products)
        outcome = subprocess.run(run["command"], timeout=150, check=False)
        drained(products)
        summary = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                  "--path", run["result"]], capture_output=True, text=True, check=True)
        counts = json.loads(summary.stdout)
        require(counts.get("totalTestCount") == 1 and counts.get("skippedTests") == 0
                and counts.get("passedTests", 0) + counts.get("failedTests", 0) == 1,
                f"Exactly one executed stage required; inspect result: {counts}")
        require((counts.get("passedTests") == 1 and counts.get("failedTests") == 0)
                if outcome.returncode == 0 else
                (counts.get("passedTests") == 0 and counts.get("failedTests") == 1),
                "Build exit and single-stage outcome disagree; inspect result")
        observation = root / (run["stage"] + ".json")
        require(observation.exists(), "No stage observation: inspect discovery/runtime failure, not capability RED")
        evidence = json.loads(observation.read_text())
        require(evidence["stage"] == run["stage"] and evidence["token"] == token
                and evidence["root"] == str(root), "Unexpected stage evidence")
        pid = evidence["pid"]
        require(type(pid) is int and pid > 0 and pid not in prior_pids, "Distinct stage host PID required")
        drained(products, stage_pid=pid)
        prior_pids.add(pid)
        with (products / ("t2381-closed-" + run["stage"] + "-drained.json")).open("x") as stream:
            stream.write(json.dumps(dict(observation=evidence, hostDrained=True,
                                         xcodebuildExit=outcome.returncode, testSummary=counts), indent=2) + "\n")
        require(outcome.returncode == 0, "Stage failed; inspect xcresult and schemaEntities; stop without cleanup")
        if run["stage"] in ("upgrade", "reopen"):
            counts = graph_rows(root)
            with (products / ("t2381-empty-graph-" + run["stage"] + ".json")).open("x") as stream:
                stream.write(json.dumps(counts, indent=2) + "\n")


if __name__ == "__main__":
    main()
