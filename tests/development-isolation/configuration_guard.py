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
for configuration in objects.values():
    if configuration.get("isa") == "XCBuildConfiguration":
        assert configuration["buildSettings"]["DEVELOPMENT_TEAM"] == "4PJS97G236"
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
            assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.apps.Transit.development"
            assert settings["TRANSIT_DEVELOPMENT_CLOUD_SYNC"] == "NO"
            assert settings["CODE_SIGN_ENTITLEMENTS"] == "$(TRANSIT_DEVELOPMENT_ENTITLEMENTS_$(TRANSIT_DEVELOPMENT_CLOUD_SYNC))"
            entitlements = plistlib.loads((root / "Transit" / settings["TRANSIT_DEVELOPMENT_ENTITLEMENTS_NO"]).read_bytes())
            for suffix, push_key in [("", "aps-environment"), ("[sdk=macosx*]", "com.apple.developer.aps-environment")]:
                cloud = plistlib.loads((root / "Transit" / settings["TRANSIT_DEVELOPMENT_ENTITLEMENTS_YES" + suffix]).read_bytes())
                assert cloud["com.apple.developer.icloud-container-identifiers"] == ["iCloud.me.nore.ig.apps.Transit.development"]
                assert cloud["com.apple.developer.icloud-container-environment"] == "Development"
                assert cloud[push_key] == "development"
                assert not cloud.get("com.apple.security.application-groups")
                assert ("aps-environment" if suffix else "com.apple.developer.aps-environment") not in cloud
            assert not any("icloud" in key or "aps-environment" in key or "application-groups" in key
                           for key in entitlements), entitlements
            assert settings["REGISTER_APP_GROUPS"] == "NO"
            if name == "TransitDevelopment":
                assert "TRANSIT_DEVELOPMENT" in settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
        else:
            assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.apps.Transit"
            assert settings["CODE_SIGN_ENTITLEMENTS"] == "Transit/Transit.entitlements"
            for path, push_key in [(settings["CODE_SIGN_ENTITLEMENTS"], "aps-environment"),
                                   (settings["CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"], "com.apple.developer.aps-environment")]:
                release = plistlib.loads((root / "Transit" / path).read_bytes())
                assert release["com.apple.developer.icloud-container-identifiers"] == ["iCloud.me.nore.ig.apps.Transit"]
                assert release["com.apple.developer.icloud-container-environment"] == "Development"
                assert release[push_key] == "development"
                assert ("aps-environment" if push_key.startswith("com.apple.") else "com.apple.developer.aps-environment") not in release
        assert settings["ENABLE_USER_SELECTED_FILES"] == "readwrite"
        mac_path = (settings["TRANSIT_DEVELOPMENT_ENTITLEMENTS_NO[sdk=macosx*]"] if isolated
                    else settings["CODE_SIGN_ENTITLEMENTS[sdk=macosx*]"])
        mac = plistlib.loads((root / "Transit" / mac_path).read_bytes())
        assert mac["com.apple.security.files.bookmarks.app-scope"] is True
        assert "aps-environment" not in mac
        if isolated:
            assert not any("icloud" in key or "aps-environment" in key for key in mac)
            cloud_mac = plistlib.loads((root / "Transit" / settings[
                "TRANSIT_DEVELOPMENT_ENTITLEMENTS_YES[sdk=macosx*]"]).read_bytes())
            assert cloud_mac["com.apple.security.files.bookmarks.app-scope"] is True
        # Keep Mac-only bookmark capabilities out of phone signing inputs.
        phone_path = settings["TRANSIT_DEVELOPMENT_ENTITLEMENTS_NO"] if isolated else settings["CODE_SIGN_ENTITLEMENTS"]
        phone = plistlib.loads((root / "Transit" / phone_path).read_bytes())
        assert "com.apple.security.files.bookmarks.app-scope" not in phone
        assert not any(key.startswith("com.apple.security.network.") for key in phone)
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
    assert settings["PRODUCT_BUNDLE_IDENTIFIER"] == "me.nore.ig.apps.Transit.development.smoke-tests"
    assert "TransitDevelopment.app/" in settings["TEST_HOST"]
print("Development identity, entitlements, test launch configuration and guarded allocator wiring passed")

sync = (root / "Transit/Transit/Services/SyncManager.swift").read_text()
assert "return try IsolatedPersistenceConfiguration.make(" in sync
assert "return ModelConfiguration(" not in sync, "No implicit Release store selection"
for target in objects.values():
    if target.get("isa") != "PBXNativeTarget" or target.get("productType") == "com.apple.product-type.application":
        continue
    for identifier in objects[target["buildConfigurationList"]]["buildConfigurations"]:
        bundle = objects[identifier]["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"]
        assert bundle.startswith("me.nore.ig.apps.Transit"), bundle
print("New-team Release/development/test identities and explicit Release storage routing passed")

# Custom destination fields must live in source plists: arbitrary INFOPLIST_KEY settings are not emitted.
for relative in ["Transit/Transit/Info.plist", "Transit/Configuration/DevelopmentInfo.plist"]:
    metadata = plistlib.loads((root / relative).read_bytes())
    assert metadata["TransitSigningTeam"] == "$(DEVELOPMENT_TEAM)"
    assert metadata["TransitCloudEnvironment"] == "Development"
print("Migration source-plist destination metadata passed")
