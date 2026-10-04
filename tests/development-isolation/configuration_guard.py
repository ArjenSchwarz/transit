"""Reject development/test build configuration that can share production identity."""
import json
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[2]
project = root / "Transit/Transit.xcodeproj/project.pbxproj"
objects = json.loads(subprocess.check_output(
    ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project)]
))["objects"]
found = set()
for target in objects.values():
    if target.get("isa") != "PBXNativeTarget" or target.get("productType") != "com.apple.product-type.application":
        continue
    name = target["name"]
    found.add(name)
    configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
    for identifier in configurations:
        configuration = objects[identifier]
        settings = configuration["buildSettings"]
        isolated = name == "TransitDevelopment" or configuration["name"] == "Debug"
        if isolated:
            assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.Transit.development"
            entitlements = plistlib.loads((root / "Transit" / settings["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
            assert not any("icloud" in key or "aps-environment" in key or "application-groups" in key
                           for key in entitlements), entitlements
            assert settings["REGISTER_APP_GROUPS"] == "NO"
            if name == "TransitDevelopment":
                assert "TRANSIT_DEVELOPMENT" in settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
        else:
            assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.Transit"
            assert settings["CODE_SIGN_ENTITLEMENTS"] == "Transit/Transit.entitlements"
assert {"Transit", "TransitDevelopment"}.issubset(found)
scheme = ET.parse(root / "Transit/Transit.xcodeproj/xcshareddata/xcschemes/Transit.xcscheme")
test_action = scheme.find("TestAction")
assert test_action.attrib["buildConfiguration"] == "Debug"
variables = test_action.findall("EnvironmentVariables/EnvironmentVariable")
assert any(v.attrib == {"key": "TRANSIT_PERSISTENCE_MODE", "value": "unit-test", "isEnabled": "YES"}
           for v in variables)
for file in (root / "Transit/TransitUITests").glob("*.swift"):
    source = file.read_text()
    if "let app = XCUIApplication()" in source:
        assert 'app.launchEnvironment["TRANSIT_PERSISTENCE_MODE"] = "ui-test"' in source, file
app = (root / "Transit/Transit/TransitApp.swift").read_text()
assert "AppDisplayIDAllocators.make(mode: mode, syncActive: cloudSyncActive)" in app
assert "DisplayIDAllocator(" not in app, "App bootstrap must use the guarded allocator factory"
smoke_scheme = ET.parse(root / "Transit/Transit.xcodeproj/xcshareddata/xcschemes/TransitIsolationSmoke.xcscheme")
smoke_action = smoke_scheme.find("TestAction")
assert smoke_action.attrib["buildConfiguration"] == "Debug"
assert any(v.attrib == {"key": "TRANSIT_PERSISTENCE_MODE", "value": "unit-test", "isEnabled": "YES"}
           for v in smoke_action.findall("EnvironmentVariables/EnvironmentVariable"))
smoke = next(t for t in objects.values() if t.get("name") == "TransitIsolationSmokeTests"
             and t.get("isa") == "PBXNativeTarget")
assert len(smoke["fileSystemSynchronizedGroups"]) == 1
assert objects[smoke["fileSystemSynchronizedGroups"][0]]["path"] == "TransitIsolationSmokeTests"
for identifier in objects[smoke["buildConfigurationList"]]["buildConfigurations"]:
    settings = objects[identifier]["buildSettings"]
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.Transit.development.smoke-tests"
    assert "TransitDevelopment.app/" in settings["TEST_HOST"]
print("Development identity, entitlements, test launch configuration and guarded allocator wiring passed")
