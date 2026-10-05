"""Prepare only bounded repair-evidence maintenance tests behind the shared signed unit-host guard; never launches."""

import json
import pathlib
import plistlib
import sys

from prepare_unit_run import require, validated_unit_run


def main():
    require(len(sys.argv) == 3, "Build-products path and RED/GREEN run tag required")
    tag = sys.argv[2]
    require(tag in ("red", "green"), "Exact RED/GREEN run tag required")
    products = pathlib.Path(sys.argv[1]).resolve()
    derived = products / f"T1734Evidence-{tag}.xctestrun"
    result = products / f"T1734Evidence-{tag}.xcresult"
    preflight = products / f"t1734-evidence-{tag}-preflight.json"
    for output in (derived, result, preflight):
        require(not output.exists() and not output.is_symlink(), f"Fresh output required: {output}")
    configuration, unit, host, info, entitlements, source = validated_unit_run(products)
    suites = ["TaskLinkRemovalEvidenceTests"]
    unit["OnlyTestIdentifiers"] = suites
    environment = unit["EnvironmentVariables"]
    for flag in ("T1734_TRANSACTION_DIAGNOSTIC", "T1734_TRANSACTION_ABORT_DIAGNOSTIC",
                 "T1734_GRAPH_BOUNDARY_RED"):
        environment.pop(flag, None)
    environment.pop("T1734_OUTSIDE_WRITER_OBSERVATIONS", None)
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(derived),
               "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
               *[f"-only-testing:TransitTests/{suite}" for suite in suites],
               "-resultBundlePath", str(result)]
    evidence = dict(host=str(host), bundleID=info["CFBundleIdentifier"], entitlements=entitlements,
                    sourceXctestrun=str(source), suites=suites, expectedExpandedCases=7,
                    expectedSkips=0, launched=False, outsideWriterExclusion=False,
                    primitiveDiagnosticsExcluded=True, derivedXctestrun=str(derived),
                    resultBundlePath=str(result), expectedCommand=command)
    with derived.open("xb") as stream:
        plistlib.dump(configuration, stream)
    with preflight.open("x") as stream:
        stream.write(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
