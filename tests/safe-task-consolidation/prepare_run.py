"""Select only consolidation suites after the established signed host preflight."""
import json
import pathlib
import plistlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "typed-task-links"))
from prepare_unit_run import require, validated_unit_run

products = pathlib.Path(sys.argv[1]).resolve()
tag = sys.argv[2]
require(tag in ("red", "green", "owned-red", "owned-green", "codec-green", "codec-green2", "owned-red2", "owned-red-full", "foundation-green", "owned-red-full2", "owned-green2", "receipt-regression", "owned-green3", "receipt-regression2", "review-fix-red", "review-fix-green", "owned-green4", "foundation-green2", "review-fix-green2", "planner-red", "planner-green", "capture-red", "capture-green", "capture-red2", "capture-green2", "capture-green3", "capture-green4", "capture-green5", "read-lifecycle-regression", "preview-retention-red", "preview-retention-green", "preview-red", "preview-green", "preview-integration-red", "preview-integration-green", "retention-budget-green", "capture-whitespace-red", "retention-budget-green2", "preview-resume-red", "preview-resume-green", "preview-canonical-red", "preview-canonical-green", "preview-critic-red", "preview-critic-green", "preview-final-green", "capture-empty-red", "preview-final-green2", "phase2-apply-green", "phase2-undo-green", "phase2-composed-green", "phase2-authority-red", "phase2-authority-green", "phase2-composed-green2", "receipt-kind-red", "receipt-kind-green"), "Unknown run tag")
configuration, unit, host, info, entitlements, source = validated_unit_run(products)
suites = ["TaskConsolidationHistoryTests"] if tag == "red" else [
    "TaskConsolidationHistoryTests", "TaskConsolidationCodecTests"]
if tag.startswith("owned"):
    suites = ["TaskConsolidationOwnedCommitTests"]
if tag.startswith("receipt-regression"):
    suites = ["MCPWriteCoordinatorTests"]
if tag.startswith("review-fix"):
    suites = ["TaskConsolidationReviewFixTests"]
if tag.startswith("planner"):
    suites = ["TaskConsolidationPlannerTests"]
if tag.startswith("capture"):
    suites = ["TaskConsolidationCaptureTests", "TaskConsolidationReadLifecycleTests"]
if tag == "read-lifecycle-regression":
    suites = ["MCPReadCoordinatorTests", "TaskLinkReadCaptureTests", "MCPReadDiagnosticsTests"]
if tag.startswith("preview-retention"):
    suites = ["ReviewRetentionTests"]
if tag in ("preview-red", "preview-green"):
    suites = ["ReviewRetentionTests", "TaskConsolidationPreviewTests"]
if tag.startswith("preview-integration") or tag.startswith("preview-resume") or tag.startswith("preview-canonical") or tag.startswith("preview-critic"):
    suites = ["ReviewRetentionTests", "TaskConsolidationPreviewTests", "ConsolidationPreviewPublicationTests", "ConsolidationCaptureAggregateTests"]
if tag in ("preview-final-green", "preview-final-green2"):
    suites = ["ReviewRetentionTests", "TaskConsolidationPreviewTests", "ConsolidationPreviewPublicationTests", "ConsolidationCaptureAggregateTests", "TaskConsolidationCaptureTests", "MCPReadCaptureBuilderTests", "MCPReadCaptureScopeTests"]
if tag in ("retention-budget-green", "retention-budget-green2"):
    suites = ["ReviewRetentionTests", "ConsolidationCaptureAggregateTests", "TaskConsolidationCaptureTests", "TaskConsolidationReadLifecycleTests"]
if tag in ("capture-whitespace-red", "capture-empty-red"):
    suites = ["ConsolidationCaptureAggregateTests"]
if tag == "phase2-apply-green":
    suites = ["TaskConsolidationApplyTests"]
if tag == "phase2-undo-green":
    suites = ["TaskConsolidationUndoTests"]
if tag.startswith("phase2-authority"):
    suites = ["TaskConsolidationApplyTests", "TaskConsolidationUndoTests"]
if tag in ("phase2-composed-green", "phase2-composed-green2"):
    suites = ["TaskConsolidationApplyTests", "TaskConsolidationUndoTests", "MCPConsolidationContractTests",
              "MCPConsolidationReceiptTests", "MCPConsolidationAppCapabilityTests",
              "TaskConsolidationNativeStateTests", "TaskConsolidationReadLifecycleTests", "TaskConsolidationEndToEndTests",
              "TaskConsolidationWireResultTests"]
if tag.startswith("receipt-kind"):
    suites = ["MCPConsolidationReceiptTests"]
unit["OnlyTestIdentifiers"] = suites
run = products / ("T2381-" + tag + ".xctestrun")
result = products / ("T2381-" + tag + ".xcresult")
require(not run.exists() and not result.exists(), "Fresh run outputs required")
with run.open("xb") as stream:
    plistlib.dump(configuration, stream)
print(json.dumps(dict(run=str(run), result=str(result), suites=suites, host=str(host),
                     bundleID=info["CFBundleIdentifier"], entitlements=entitlements)))
