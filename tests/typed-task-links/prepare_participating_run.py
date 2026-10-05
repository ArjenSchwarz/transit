"""Prepare the amended task3 cases from fresh signed shared Transit Debug products.

This never launches a host. After the parent assigns a bounded exclusive slot:
  python3 tests/typed-task-links/prepare_participating_run.py FRESH_BUILD_PRODUCTS
  xcodebuild test-without-building -xctestrun FRESH_BUILD_PRODUCTS/T1734Participating.xctestrun \
    -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
    -only-testing:TransitTests/TaskLinkProtectedBoundaryTests \
    -only-testing:TransitTests/TaskLinkParticipatingBoundaryTests \
    -resultBundlePath FRESH_BUILD_PRODUCTS/T1734Participating.xcresult

Expected inventory: 15 expanded cases, zero skips, across two selected suites.
The existing-policy stale-source case is an actual-SUT RED expectation until
runtime proves otherwise. The two outside-writer cases observe allowed races,
not projection diagnostics. Primitive diagnostics are excluded from this job.
Use the parent's timeout/sample/owned-PID drain wrapper around xcodebuild.
The parent launcher also sanitizes inherited T1734 flags; this helper sets the
outside-writer flag only in the derived run file. Prepare once, then consume
that file: do not rerun preparation against its already reserved output paths.
"""

import json
import pathlib
import plistlib
import sys

from prepare_unit_run import require, validated_unit_run


def main():
    require(len(sys.argv) == 2, "One fresh build-products path required")
    products = pathlib.Path(sys.argv[1]).resolve()
    derived = products / "T1734Participating.xctestrun"
    result = products / "T1734Participating.xcresult"
    preflight = products / "t1734-participating-preflight.json"
    for output in (derived, result, preflight):
        require(not output.exists() and not output.is_symlink(), f"Fresh output required: {output}")
    configuration, unit, host, info, entitlements, source = validated_unit_run(products)
    suites = ["TaskLinkProtectedBoundaryTests", "TaskLinkParticipatingBoundaryTests"]
    unit["OnlyTestIdentifiers"] = suites
    environment = unit["EnvironmentVariables"]
    for flag in ("T1734_TRANSACTION_DIAGNOSTIC", "T1734_TRANSACTION_ABORT_DIAGNOSTIC",
                 "T1734_GRAPH_BOUNDARY_RED"):
        environment.pop(flag, None)
    environment["T1734_OUTSIDE_WRITER_OBSERVATIONS"] = "1"
    command = ["xcodebuild", "test-without-building", "-xctestrun", str(derived),
               "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
               "-only-testing:TransitTests/TaskLinkProtectedBoundaryTests",
               "-only-testing:TransitTests/TaskLinkParticipatingBoundaryTests",
               "-resultBundlePath", str(result)]
    evidence = dict(host=str(host), bundleID=info["CFBundleIdentifier"], entitlements=entitlements,
                    sourceXctestrun=str(source), suites=suites, expectedExpandedCases=15,
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
