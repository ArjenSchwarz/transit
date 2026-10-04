"""Bounded offline verification; production files are denied to every child."""
import json
import os
import pathlib
import selectors
import sqlite3
import subprocess
import sys
import tempfile


def main():
    policy, migration, bootstrap, output = map(lambda p: pathlib.Path(p).resolve(), sys.argv[1:])
    cache_root = output.parent
    temporary = cache_root / "tmp"
    temporary.mkdir(parents=True, exist_ok=True)
    production = pathlib.Path.home() / "Library/Containers/me.nore.ig.Transit"
    groups = pathlib.Path.home() / "Library/Group Containers"
    profile = '(version 1)(allow default)(deny network*)' + ''.join(
        '(deny file-read* file-write* (subpath ' + json.dumps(str(p)) + '))'
        for p in (production, groups)
    )
    prefix = ["/usr/bin/sandbox-exec", "-p", profile]
    subprocess.run(prefix + ["/usr/bin/true"], check=True, timeout=5)
    results = {"cloudKit": "none", "network": "denied by sandbox-exec",
               "liveContainer": "denied by sandbox-exec", "cases": []}
    results["policy"] = subprocess.check_output(prefix + [str(policy)], text=True, timeout=10).strip()
    results["bootstrap"] = subprocess.check_output(prefix + [str(bootstrap)], text=True, timeout=15).strip()
    with tempfile.TemporaryDirectory(prefix="transit-synthetic-", dir=temporary) as disposable:
        root = pathlib.Path(disposable).resolve()
        environment = dict(os.environ, TRANSIT_DISPOSABLE_ROOT=str(root))

        def execute(mode, store):
            run = subprocess.run(prefix + [str(migration), mode, str(store)],
                                 env=environment, capture_output=True, text=True, timeout=15)
            return {"mode": mode, "exit": run.returncode,
                    "stdout": run.stdout, "stderr": run.stderr[-8000:]}

        configuration_root = root / "configuration"
        configuration_root.mkdir()
        results["pathGuard"] = execute("path-guard", configuration_root / "synthetic.store")
        if results["pathGuard"]["exit"]:
            raise RuntimeError(results["pathGuard"])
        results["configuration"] = execute("configuration", configuration_root / "synthetic.store")

        def metadata(store):
            connection = sqlite3.connect(store.as_uri() + "?mode=ro", uri=True)
            try:
                return {
                    "entities": connection.execute("SELECT Z_ENT,Z_NAME FROM Z_PRIMARYKEY").fetchall(),
                    "taskEntityCounts": connection.execute(
                        "SELECT Z_ENT,count(*) FROM ZTRANSITTASK GROUP BY Z_ENT").fetchall(),
                    "taskUUIDDuplicates": connection.execute(
                        "SELECT count(*) FROM (SELECT ZID FROM ZTRANSITTASK GROUP BY ZID HAVING count(*)>1)"
                    ).fetchone()[0],
                    "quickCheck": connection.execute("PRAGMA quick_check").fetchone()[0],
                }
            finally:
                connection.close()

        for concurrent in (False, True):
            case_root = root / ("concurrent" if concurrent else "sequential")
            case_root.mkdir()
            store = case_root / "synthetic.store"
            case = {"name": case_root.name, "seed": execute("seed-old", store)}
            if case["seed"]["exit"]:
                raise RuntimeError(case["seed"])
            case["before"] = metadata(store)
            old = None
            try:
                if concurrent:
                    # Stderr is a file, so diagnostic output cannot fill a pipe
                    # and prevent bounded completion of the held process.
                    with (case_root / "old-stderr.txt").open("w+") as errors:
                        old = subprocess.Popen(prefix + [str(migration), "hold-old", str(store)],
                                               env=environment, stdin=subprocess.PIPE,
                                               stdout=subprocess.PIPE, stderr=errors,
                                               text=True, bufsize=1)
                        case["oldReady"] = read_line(old)
                        case["new"] = execute("open-new", store)
                        old.stdin.write("read\nquit\n")
                        old.stdin.flush()
                        case["oldRead"] = read_line(old)
                        old.wait(timeout=10)
                        errors.seek(0)
                        case["oldExit"] = old.returncode
                        case["oldStderr"] = errors.read()[-8000:]
                else:
                    case["new"] = execute("open-new", store)
                case["after"] = metadata(store)
            except (OSError, subprocess.SubprocessError, TimeoutError) as error:
                case["error"] = str(error)
            finally:
                if old is not None:
                    if old.poll() is None:
                        old.terminate()
                        old.wait(timeout=5)
                    old.stdin.close()
                    old.stdout.close()
            results["cases"].append(case)
        baseline = results["cases"][0]
        baseline_ok = baseline.get("new", {}).get("exit") == 0 and "error" not in baseline
        if baseline_ok:
            seed = json.loads(baseline["seed"]["stdout"].strip().splitlines()[-1])
            saved = json.loads(baseline["new"]["stdout"].strip().splitlines()[-1])
            baseline_ok = (saved["taskCount"] == 1 and saved["projectCount"] == 1
                           and seed["taskRecords"] == saved["taskRecords"]
                           and seed["projectionRevisions"] == saved["projectionRevisions"]
                           and saved["receipt"]["key"] == "synthetic-key"
                           and saved["receipt"]["state"] == "accepted"
                           and saved["linkedProjectNames"] == ["Synthetic"])
        results["sequentialInvariantPassed"] = baseline_ok
    output.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    if results["configuration"]["exit"] != 0:
        raise RuntimeError("Actual isolated configuration checks failed; see saved evidence")
    if not results["sequentialInvariantPassed"]:
        raise RuntimeError("Sequential migration baseline failed; see saved evidence")


def read_line(process):
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        if not selector.select(timeout=10):
            raise TimeoutError("Disposable probe did not respond within 10 seconds")
        return process.stdout.readline().strip()


if __name__ == "__main__":
    main()
