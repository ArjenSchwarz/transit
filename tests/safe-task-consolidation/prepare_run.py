"""Select only consolidation suites after the established signed host preflight."""
import json
import pathlib
import plistlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "typed-task-links"))
from prepare_unit_run import require, validated_unit_run

products = pathlib.Path(sys.argv[1]).resolve()
tag = sys.argv[2]
require(tag in ("red", "green", "owned-red", "owned-green", "codec-green", "codec-green2", "owned-red2", "owned-red-full", "foundation-green", "owned-red-full2", "owned-green2", "receipt-regression", "owned-green3", "receipt-regression2"), "Unknown run tag")
configuration, unit, host, info, entitlements, source = validated_unit_run(products)
suites = ["TaskConsolidationHistoryTests"] if tag == "red" else [
    "TaskConsolidationHistoryTests", "TaskConsolidationCodecTests"]
if tag.startswith("owned"):
    suites = ["TaskConsolidationOwnedCommitTests"]
if tag.startswith("receipt-regression"):
    suites = ["MCPWriteCoordinatorTests"]
unit["OnlyTestIdentifiers"] = suites
run = products / ("T2381-" + tag + ".xctestrun")
result = products / ("T2381-" + tag + ".xcresult")
require(not run.exists() and not result.exists(), "Fresh run outputs required")
with run.open("xb") as stream:
    plistlib.dump(configuration, stream)
print(json.dumps(dict(run=str(run), result=str(result), suites=suites, host=str(host),
                     bundleID=info["CFBundleIdentifier"], entitlements=entitlements)))
