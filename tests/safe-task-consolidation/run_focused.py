"""Run explicitly selected isolated suites and reject zero or unexpected discovery."""
import json
import pathlib
import subprocess
import sys

from run_closed_store import drained
from prepare_unit_run import require

products = pathlib.Path(sys.argv[1]).resolve()
tag = sys.argv[2]
expected = int(sys.argv[3])
expect_red = len(sys.argv) == 5 and sys.argv[4] == "red"
require(expected > 0, "Positive expected test declaration count required")
prepared = subprocess.check_output([sys.executable, str(pathlib.Path(__file__).with_name("prepare_run.py")),
                                    str(products), tag], text=True)
metadata = json.loads(prepared)
command = ["xcodebuild", "test-without-building", "-xctestrun", metadata["run"],
           "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
           *[f"-only-testing:TransitTests/{suite}" for suite in metadata["suites"]],
           "-resultBundlePath", metadata["result"]]
log = products / ("T2381-" + tag + ".log")
evidence = products / ("T2381-" + tag + "-evidence.json")
require(not log.exists() and not evidence.exists(), "Fresh log/evidence required")
drained(products)
with log.open("x") as stream:
    run = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=180, check=False)
drained(products)
text = log.read_text()
require("Fatal error:" not in text and "Restarting after unexpected exit" not in text,
        "Crash/restart is invalid behavioral evidence; inspect preserved log")
summary = json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                             "--path", metadata["result"]], text=True))
observed = summary.get("totalTestCount")
require(observed == expected and summary.get("skippedTests") == 0
        and summary.get("passedTests", 0) + summary.get("failedTests", 0) == expected,
        f"Discovery/count mismatch: {summary}")
require((run.returncode != 0 and summary.get("failedTests", 0) > 0) if expect_red else
        (run.returncode == 0 and summary.get("passedTests") == expected), f"Unexpected outcome: {summary}")
metadata.update(command=command, expectedDeclarations=expected, summary=summary,
                xcodebuildExit=run.returncode, ownedProcessesDrained=True, expectedRed=expect_red)
evidence.write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(dict(evidence=str(evidence), executed=observed, passed=summary["passedTests"],
                     failed=summary["failedTests"], drained=True)))
