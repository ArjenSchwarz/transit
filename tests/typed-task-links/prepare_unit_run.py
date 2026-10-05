"""Prepare the focused migration run after parent handoff and exclusive slot release.

Run from the ticket checkout with a fresh DerivedData directory and locally
resolved packages. The shared Transit Debug scheme supplies the isolated host;
TransitDevelopment is not the unit-test scheme. This helper never launches it.

    xcodebuild build-for-testing -project Transit/Transit.xcodeproj \
      -scheme Transit -configuration Debug -destination 'platform=macOS,arch=arm64' \
      -parallel-testing-enabled NO -disableAutomaticPackageResolution \
      -derivedDataPath DerivedData/t1734-migration-red-run1
    python3 tests/typed-task-links/prepare_unit_run.py \
      DerivedData/t1734-migration-red-run1/Build/Products
    xcodebuild test-without-building \
      -xctestrun DerivedData/t1734-migration-red-run1/Build/Products/T1734Migration.xctestrun \
      -destination 'platform=macOS,arch=arm64' -parallel-testing-enabled NO \
      -only-testing:TransitTests/TaskLinkMigrationTests \
      -resultBundlePath DerivedData/t1734-migration-red-run1/Build/Products/T1734Migration.xcresult

Expected source inventory: two declarations, three parameter-expanded cases.
Missing-model assertions are prospective capability RED, not migration evidence.
Do not reuse a directory containing this helper's prior outputs or result bundle.
"""

import json
import pathlib
import plistlib
import subprocess
import sys


def require(condition, message):
    """Fail closed even if Python is invoked with optimization enabled."""
    if not condition:
        raise RuntimeError(message)


def validated_unit_run(products):
    """Revalidate signed host and return the existing unit-only migration selection."""
    host = products / "Debug/Transit.app"
    info = plistlib.loads((host / "Contents/Info.plist").read_bytes())
    require(info["CFBundleIdentifier"] == "me.nore.ig.Transit.development", "Unexpected host identity")
    require(info["CFBundleExecutable"] == "Transit", "Unexpected host executable")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(host)], check=True)
    signature = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(host)],
        capture_output=True, check=True,
    )
    entitlements = plistlib.loads(signature.stdout)
    require(not any("icloud" in key or "aps-environment" in key or "application-groups" in key
                    for key in entitlements), f"Unsafe entitlements: {entitlements}")
    require(entitlements.get("com.apple.security.get-task-allow") is True, "Development signing required")

    files = list(products.glob("Transit_*.xctestrun"))
    require(len(files) == 1, f"One shared Transit run file required: {files}")
    configuration = plistlib.loads(files[0].read_bytes())
    if "TestConfigurations" in configuration:
        targets = [target for item in configuration["TestConfigurations"] for target in item["TestTargets"]]
    else:
        targets = [value for key, value in configuration.items()
                   if not key.startswith("__") and isinstance(value, dict)]
    units = [target for target in targets if target.get("BlueprintName") == "TransitTests"]
    require(len(units) == 1, "Exactly one TransitTests unit target required")
    unit = units[0]
    require(unit.get("IsUITestBundle", False) is False, "UI test target forbidden")
    require(pathlib.Path(unit["TestHostPath"].replace("__TESTROOT__", str(products))).resolve() == host,
            "Unit target must use this exact development host")
    environment = unit.setdefault("EnvironmentVariables", {})
    require(environment.get("TRANSIT_PERSISTENCE_MODE") == "unit-test", "Unit-test persistence required")
    environment.update(TRANSIT_ISOLATION_SMOKE="1", TRANSIT_SMOKE_HOST_PATH=str(host))
    unit["OnlyTestIdentifiers"] = ["TaskLinkMigrationTests"]
    require(not unit.get("SkipTestIdentifiers"), "Unexpected skipped tests; review source run configuration")

    # Keep only the verified unit target; do not carry UI targets into the run.
    if "TestConfigurations" in configuration:
        selected = []
        for item in configuration["TestConfigurations"]:
            if any(target is unit for target in item["TestTargets"]):
                item["TestTargets"] = [unit]
                selected.append(item)
        configuration["TestConfigurations"] = selected
    else:
        configuration = {key: value for key, value in configuration.items()
                         if key.startswith("__") or value is unit}

    return configuration, unit, host, info, entitlements, files[0]


def main():
    require(len(sys.argv) == 2, "Usage: prepare_unit_run.py BUILD_PRODUCTS")
    products = pathlib.Path(sys.argv[1]).resolve()
    derived = products / "T1734Migration.xctestrun"
    evidence_path = products / "t1734-migration-preflight.json"
    result = products / "T1734Migration.xcresult"
    for output in (derived, evidence_path, result):
        require(not output.exists(), f"Fresh output path required: {output}")

    configuration, unit, host, info, entitlements, source_file = validated_unit_run(products)
    environment = unit["EnvironmentVariables"]

    evidence = dict(
        bundleID=info["CFBundleIdentifier"], host=str(host), entitlements=entitlements,
        scheme="Transit", configuration="Debug", mode=environment["TRANSIT_PERSISTENCE_MODE"],
        startupGuard=dict(TRANSIT_ISOLATION_SMOKE=environment["TRANSIT_ISOLATION_SMOKE"],
                          TRANSIT_SMOKE_HOST_PATH=environment["TRANSIT_SMOKE_HOST_PATH"]),
        sourceXctestrun=str(source_file), derivedXctestrun=str(derived), resultBundle=str(result),
        suites=["TaskLinkMigrationTests"], expectedCases=3, parallel=False, launched=False,
    )
    with derived.open("xb") as stream:
        plistlib.dump(configuration, stream)
    with evidence_path.open("x") as stream:
        stream.write(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
