"""Verify the built isolated host before a single, serial test-without-building run."""
import json
import pathlib
import plistlib
import subprocess
import sys

products = pathlib.Path(sys.argv[1]).resolve()
host = products / "Debug/TransitDevelopment.app"
info = plistlib.loads((host / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "me.nore.ig.Transit.development"
assert info["CFBundleExecutable"] == "TransitDevelopment"
subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(host)], check=True)
signature = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(host)],
                           capture_output=True, check=True)
entitlements = plistlib.loads(signature.stdout)
assert not any("icloud" in key or "aps-environment" in key or "application-groups" in key
               for key in entitlements), entitlements
assert entitlements.get("com.apple.security.get-task-allow") is True
files = list(products.glob("TransitIsolationSmoke_*.xctestrun"))
assert len(files) == 1, files
configuration = plistlib.loads(files[0].read_bytes())
targets = []
if "TestConfigurations" in configuration:
    for test_configuration in configuration["TestConfigurations"]:
        targets.extend(test_configuration["TestTargets"])
else:
    targets = [value for key, value in configuration.items()
               if not key.startswith("__") and isinstance(value, dict)]
unit = [target for target in targets if target.get("BlueprintName") == "TransitIsolationSmokeTests"]
assert len(unit) == 1, targets
unit = unit[0]
host_path = unit["TestHostPath"].replace("__TESTROOT__", str(products))
assert pathlib.Path(host_path).resolve() == host
assert unit.get("IsUITestBundle", False) is False
variables = unit.setdefault("EnvironmentVariables", {})
assert variables.get("TRANSIT_PERSISTENCE_MODE") == "unit-test", variables
variables.update(TRANSIT_ISOLATION_SMOKE="1", TRANSIT_SMOKE_HOST_PATH=str(host))
unit["OnlyTestIdentifiers"] = ["DevelopmentIsolationSmokeTests"]
launch = products / "IsolationSmoke.xctestrun"
launch.write_bytes(plistlib.dumps(configuration))
evidence = {"bundleID": info["CFBundleIdentifier"], "host": str(host),
            "entitlements": entitlements, "mode": variables["TRANSIT_PERSISTENCE_MODE"],
            "fixture": "TransitIsolationSmokeTests/DevelopmentIsolationSmokeTests", "parallel": False}
(products / "smoke-preflight.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence, indent=2), flush=True)
result = products / "IsolationSmoke.xcresult"
assert not result.exists(), "Use fresh result/DerivedData paths for a repeat smoke"
subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(launch),
                "-destination", "platform=macOS,arch=arm64", "-parallel-testing-enabled", "NO",
                "-only-testing:" + evidence["fixture"],
                "-resultBundlePath", str(result)], check=True, timeout=180)
