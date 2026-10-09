# Separate Transit environments (T-2432)

Debug and Release may coexist. Build each into its own DerivedData directory and keep both app bundles when copying them elsewhere: Debug produces `TransitDevelopment.app`; Release produces `Transit.app`. `TransitDevelopment` is also an explicit development target whose optimized builds retain Debug identity.

| Binding | Release | Debug / TransitDevelopment |
| --- | --- | --- |
| Bundle / standard defaults domain | `me.nore.ig.Transit` | `me.nore.ig.Transit.development` |
| Local SwiftData storage | Existing default configuration and URL | Existing `Application Support/TransitDevelopment/development.store` |
| CloudKit private database | `iCloud.me.nore.ig.Transit` | `iCloud.me.nore.ig.Transit.development` when opted in |
| CloudKit environment | Existing recovered **Development** dataset | **Development** in the separate container |
| Default MCP port | 3141 | 3142 |
| MCP identity / client setup name | `transit` | `transit-debug` |

Release identity, entitlements, default store selection and existing preferences are preserved. Release here names the application build, not CloudKit Production. Do not promote schemas, change its CloudKit environment, reset its container, or migrate data as part of enabling Debug. A future move of the live app to CloudKit Production requires a separately reviewed data transition.

Debug has no App Group entitlement, and its persistent configuration uses an explicit private store URL, bypassing automatic group-container selection. Standard UserDefaults (theme, name, sync preference, MCP settings) use its separate bundle domain. MCP receipts and reservation sidecars follow each selected store URL. Test modes retain in-memory storage, no cloud containers, disabled counters, disposable sidecars and no automatic MCP startup, even when a cloud-capable development binary is used.

## Enable the dedicated Debug cloud backend

Ordinary Debug remains local-only until the new Apple capabilities are ready. The single build setting `TRANSIT_DEVELOPMENT_CLOUD_SYNC=YES` selects both the platform-correct dedicated cloud entitlement file and the corresponding startup flag. Settings identifies the running app and active backend. No fallback redirects Debug to the Release container.

Required developer setup (manual, once):

1. In Apple Developer for team `V24684SCZN`, register/verify App ID `me.nore.ig.Transit.development` and iCloud container `iCloud.me.nore.ig.Transit.development`.
2. Enable CloudKit and Push Notifications for that development App ID, associate **only** the new container, and refresh the development profiles for the platforms you use. Do not modify the Release App ID or its container association.
3. Set `TRANSIT_DEVELOPMENT_CLOUD_SYNC=YES` for your development build, using the existing development signing identity. For example:

```sh
xcodebuild build -project Transit/Transit.xcodeproj -scheme TransitDevelopment \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData/DebugCloud TRANSIT_DEVELOPMENT_CLOUD_SYNC=YES
```

The source prepares `DevelopmentCloud.entitlements` for iOS and `DevelopmentCloudMac.entitlements` for macOS, each explicitly selecting CloudKit Development and only the dedicated Debug container. This implementation does not create Apple resources, auto-register profiles, initialize a schema on a live cloud account during verification, launch production, or install either app. Actual Debug cloud sync must be checked after this setup; an unsigned build cannot demonstrate iCloud access.

Keep `TRANSIT_DEVELOPMENT_CLOUD_SYNC=NO` for local-only development and routine tests. Unit/UI test launch policy prohibits CloudKit regardless of the build setting. Turning sync on/off remains restart-scoped; the current store and ID counter retain their launch-fixed backend until relaunch.

## MCP connections

On first use, enable each app's MCP server in its own Settings. The selected valid port is persisted in that app's defaults domain; existing explicit overrides are preserved, including an intentionally shared port (the server reports a bind failure). Different defaults prevent a collision without rewriting a user's port choice.

```sh
claude mcp add transit --transport http http://localhost:3141/mcp
claude mcp add transit-debug --transport http http://localhost:3142/mcp
```

Use the running listener's port shown in Settings if overridden. MCP `server/discover` identifies development binaries as `transit-debug`, including optimized `TransitDevelopment` builds. Settings reports `Debug`, `Release`, or the isolated test environment along with the active cloud container or local-only status.

## Verification boundaries

`make test-development-configuration` audits bundle IDs, build flags, entitlements and test launches. `make test-development-isolation` uses synthetic stores under a network-denying sandbox and denies access to the Release container and Group Containers. Unit regression fixtures check independent MCP defaults and explicit overrides, invalid Debug cloud binding rejection, and the existing sync launch behavior. Tests do not open recovered Release storage or contact either CloudKit backend.
