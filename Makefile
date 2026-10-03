# Transit Makefile

SHELL = /bin/bash
.SHELLFLAGS = -eo pipefail -c

SCHEME = Transit
PROJECT = Transit/Transit.xcodeproj
BUNDLE_ID = me.nore.ig.Transit
CONFIG ?= Debug

# Pipe through xcbeautify if available, otherwise raw output
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
ifdef XCBEAUTIFY
PIPE_PRETTY = | xcbeautify
else
PIPE_PRETTY =
endif

# macOS ships GNU Make 3.81, which ignores .SHELLFLAGS. Enable pipefail in
# each recipe that may pipe xcodebuild through xcbeautify so failures propagate.
PIPEFAIL = set -o pipefail;

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo ""
	@echo "  Development (Debug):"
	@echo "    lint        - Run SwiftLint"
	@echo "    lint-fix    - Run SwiftLint with auto-fix"
	@echo "    build-ios   - Build for iOS Simulator"
	@echo "    build-macos - Build for macOS"
	@echo "    build       - Build for both platforms"
	@echo "    test-quick  - Run unit tests on macOS (fast)"
	@echo "    test        - Run full test suite on iOS Simulator"
	@echo "    test-ui     - Run UI tests only"
	@echo "    install     - Build and install Debug on device"
	@echo "    run         - Build, install, and launch Debug on device"
	@echo ""
	@echo "  Release:"
	@echo "    install-release     - Build and install Release on device"
	@echo "    run-release         - Build, install, and launch Release on device"
	@echo "    build-macos-release - Build Release for macOS"
	@echo "    run-macos-release   - Build and launch Release on macOS"
	@echo ""
	@echo "  Distribution:"
	@echo "    archive  - Create xcarchive for iOS"
	@echo "    upload   - Archive and upload to App Store Connect"
	@echo ""
	@echo "  Utilities:"
	@echo "    clean    - Clean build artifacts"
	@echo ""
	@echo "Device targets use DEVICE_MODEL (default: iPhone 17 Pro)"
	@echo "Override with: make install DEVICE_MODEL='iPhone 16'"

# Linting
#
# SwiftLint defaults to ~/Library/Caches/SwiftLint, which is outside the
# workspace and may not be writable in sandboxed agent environments. Pin the
# cache to a workspace-local, gitignored directory so `make lint` is
# reproducible across interactive, CI, and sandboxed runs.
SWIFTLINT_CACHE = .swiftlint-cache

.PHONY: test-model-container-ownership-guard
test-model-container-ownership-guard:
	bash tests/validation/test_model_container_ownership_guard.sh

# App test runners cannot reliably read host checkout files. Keep source-literal
# validation in the repository process before linting or launching tests.
.PHONY: test-create-task-project-schema-guard
test-create-task-project-schema-guard:
	python3 tests/validation/create_task_project_schema_guard.py

.PHONY: lint
lint: test-model-container-ownership-guard test-create-task-project-schema-guard
	swiftlint lint --strict --cache-path $(SWIFTLINT_CACHE)

.PHONY: lint-fix
lint-fix: test-model-container-ownership-guard
	swiftlint lint --fix --strict --cache-path $(SWIFTLINT_CACHE)

# Building
DERIVED_DATA = ./DerivedData

# Workspace-local cache locations. Xcode and its subprocesses (SwiftPM, Clang)
# otherwise scatter caches across ~/Library/Caches and ~/.cache, which fail in
# sandboxed/dev environments. Keep everything under DerivedData so a single
# `make clean` is enough. See T-1241 and T-1628.
WORKSPACE_CACHE = $(DERIVED_DATA)/Caches
WORKSPACE_TMP = $(DERIVED_DATA)/tmp
SPM_MANIFEST_MODULE_CACHE = $(WORKSPACE_CACHE)/org.swift.swiftpm
CLANG_MODULE_CACHE = $(DERIVED_DATA)/ModuleCache.noindex

# -clonedSourcePackagesDirPath and -packageCachePath are intentionally omitted:
# they expect the SourcePackages parent dir (not its checkouts/cache subdirs),
# and supplying both silently disables xcodebuild's package resolve step. With
# only -derivedDataPath set, xcodebuild places SourcePackages under
# $(DERIVED_DATA), which already keeps package checkouts and repository data
# workspace-local.
#
# CLANG_MODULE_CACHE_PATH must be an xcodebuild build setting, not just an
# environment variable, so the compiler receives the module-cache path.
XCODEBUILD_CACHE_FLAGS = \
	-derivedDataPath $(DERIVED_DATA) \
	CLANG_MODULE_CACHE_PATH=$(abspath $(CLANG_MODULE_CACHE))

# Exported before every xcodebuild call so XDG cache fallbacks, compiler temp
# files, and SwiftPM manifest compilation (including *.dia diagnostics) stay
# inside the workspace. SWIFTPM_MODULECACHE_OVERRIDE is recognized by SwiftPM;
# Xcode's own Clang cache is configured above as a build setting.
XCODEBUILD_ENV = \
	XDG_CACHE_HOME=$(abspath $(WORKSPACE_CACHE)) \
	TMPDIR=$(abspath $(WORKSPACE_TMP)) \
	SWIFTPM_MODULECACHE_OVERRIDE=$(abspath $(SPM_MANIFEST_MODULE_CACHE))

.PHONY: prepare-cache-dirs
prepare-cache-dirs:
	@mkdir -p $(WORKSPACE_CACHE) $(WORKSPACE_TMP) $(SPM_MANIFEST_MODULE_CACHE) $(CLANG_MODULE_CACHE)

.PHONY: build-ios
build-ios: prepare-cache-dirs
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration $(CONFIG) \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(PIPE_PRETTY)

.PHONY: build-macos
build-macos: prepare-cache-dirs
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild build \
		-allowProvisioningUpdates \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration $(CONFIG) \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(PIPE_PRETTY)

.PHONY: build
build: build-ios build-macos

# Testing
# Nested macro sandboxing is unavailable in some already-sandboxed runners.
# Set MCP_PROBE_SWIFT_FLAGS=-disable-sandbox there; the outer runner policy stays active.
MCP_PROBE_SWIFT_FLAGS ?=
MCP_PROBE_MODELS = Transit/Transit/Models/{Project,TransitTask,Comment,Milestone,SyncHeartbeat,DisplayID,TaskPriority,TaskStatus,TaskType,MilestoneStatus,MCPWriteReceipt}.swift
.PHONY: test-mcp-write-guards
test-mcp-write-guards: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -parse-as-library -default-isolation MainActor -module-cache-path $(CLANG_MODULE_CACHE) \
		Transit/Transit/MCP/Writes/{MCPCanonicalJSON,MCPLocalReservationStore}.swift tests/mcp-write-probe/GuardProbe.swift \
		-o $(DERIVED_DATA)/mcp-write-guard-probe
	python3 tests/mcp-write-probe/guards.py $(DERIVED_DATA)/mcp-write-guard-probe

.PHONY: test-mcp-write-foundation
test-mcp-write-foundation: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -parse-as-library -default-isolation MainActor -module-cache-path $(CLANG_MODULE_CACHE) \
		$(MCP_PROBE_MODELS) Transit/Transit/MCP/Writes/{MCPCanonicalJSON,MCPRecordSnapshot,MCPRecordRevision,MCPLocalReservationStore,MCPWriteReceiptStore}.swift \
		Transit/Transit/Services/CommentService.swift Transit/Transit/Extensions/ModelContext+{Save,SafeRollback}.swift \
		tests/mcp-write-probe/FoundationProbe.swift -o $(DERIVED_DATA)/mcp-write-foundation-probe
	$(DERIVED_DATA)/mcp-write-foundation-probe

.PHONY: test-mcp-write-services
MCP_PROBE_SERVICES = Transit/Transit/Services/{TaskService,TaskService+Error,MilestoneService,MilestoneService+Error,ProjectService,CommentService,ModelFetching,UsedDisplayIDs,DisplayIDAllocator,DisplayIDRecordLookup,CloudKitCounterStore,CreationProjectValidator,TaskCreationMilestoneValidator,ProjectNameReconciler,MilestoneNameReconciler,StatusEngine,PersistenceAvailability,ContainerFactory}.swift
MCP_PROBE_DEPENDENCIES ?= $(DERIVED_DATA)/Build/Products/Debug
.PHONY: format-mcp-write
format-mcp-write:
	xcrun swift-format format --in-place --configuration tests/mcp-write-probe/swift-format.json \
		Transit/Transit/MCP/Writes/{MCPWriteCommand,MCPWriteCoordinator,MCPWriteOutcome}.swift \
		Transit/Transit/MCP/{MCPToolDefinitions,MCPToolHandler,MCPTypes}.swift \
		Transit/TransitTests/{MCPWriteCoordinatorTests,MCPWriteContractTests}.swift \
		tests/mcp-write-probe/CoordinatorProbe.swift

.PHONY: check-mcp-write-handler
.PHONY: check-mcp-write-lifecycle-syntax
check-mcp-write-lifecycle-syntax:
	xcrun swiftc -frontend -parse -swift-version 6 Transit/Transit/TransitApp.swift Transit/TransitTests/*.swift

.PHONY: check-mcp-write-handler-syntax
check-mcp-write-handler-syntax:
	xcrun swiftc -frontend -parse -swift-version 6 \
		Transit/Transit/MCP/{MCPToolHandler,MCPToolHandler+TaskQuery,MCPTaskQueryRequest,MCPTaskQuerySnapshotStore,MCPToolDefinitions,MCPTypes}.swift

check-mcp-write-handler: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -swift-version 6 -typecheck -default-isolation MainActor \
		-module-cache-path $(CLANG_MODULE_CACHE) -I $(MCP_PROBE_DEPENDENCIES) \
		$(MCP_PROBE_MODELS) $(MCP_PROBE_SERVICES) Transit/Transit/MCP/Writes/*.swift \
		Transit/Transit/MCP/{MCPTypes,MCPToolDefinitions,MCPToolHandler,MCPToolHandler+TaskQuery,MCPTaskQueryRequest,MCPTaskQuerySnapshotStore,MCPSettings,MCPToolListChangeBroadcaster,MCPHelperTypes}.swift \
		Transit/Transit/Services/{DisplayIDMaintenanceService,DisplayIDMaintenanceTypes}.swift \
		Transit/Transit/Intents/{IntentHelpers,IntentError,TaskUpdateValidator,QueryMilestonesIntent}.swift \
		Transit/Transit/Intents/Shared/TaskFetching.swift \
		Transit/Transit/Extensions/ModelContext+{Save,SafeRollback}.swift

.PHONY: test-mcp-write-coordinator
test-mcp-write-coordinator: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -swift-version 6 -parse-as-library -default-isolation MainActor -module-cache-path $(CLANG_MODULE_CACHE) \
		$(MCP_PROBE_MODELS) $(MCP_PROBE_SERVICES) Transit/Transit/MCP/Writes/*.swift \
		Transit/Transit/MCP/{MCPTypes,MCPToolDefinitions}.swift \
		Transit/Transit/Intents/{IntentHelpers,IntentError,TaskUpdateValidator}.swift \
		Transit/Transit/Extensions/ModelContext+{Save,SafeRollback}.swift \
		tests/mcp-write-probe/{CoordinatorProbe,CoordinatorRegressionProbe}.swift -o $(DERIVED_DATA)/mcp-write-coordinator-probe
	$(DERIVED_DATA)/mcp-write-coordinator-probe

test-mcp-write-services: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -parse-as-library -default-isolation MainActor -module-cache-path $(CLANG_MODULE_CACHE) \
		$(MCP_PROBE_MODELS) Transit/Transit/Services/{TaskService,TaskService+Error,MilestoneService,MilestoneService+Error,ProjectService,CommentService,ModelFetching,UsedDisplayIDs,DisplayIDAllocator,DisplayIDRecordLookup,CloudKitCounterStore,CreationProjectValidator,TaskCreationMilestoneValidator,ProjectNameReconciler,MilestoneNameReconciler,StatusEngine,PersistenceAvailability,ContainerFactory}.swift \
		Transit/Transit/Intents/{IntentHelpers,IntentError}.swift Transit/Transit/Extensions/ModelContext+{Save,SafeRollback}.swift \
		tests/mcp-write-probe/ServiceProbe.swift -o $(DERIVED_DATA)/mcp-write-service-probe
	$(DERIVED_DATA)/mcp-write-service-probe

.PHONY: test-mcp-write-persistence
test-mcp-write-persistence: prepare-cache-dirs
	xcrun swiftc $(MCP_PROBE_SWIFT_FLAGS) -parse-as-library -default-isolation MainActor -module-cache-path $(CLANG_MODULE_CACHE) \
		$(MCP_PROBE_MODELS) \
		Transit/Transit/Extensions/ModelContext+SafeRollback.swift tests/mcp-write-probe/Probe.swift \
		-o $(DERIVED_DATA)/mcp-write-disk-probe
	python3 tests/mcp-write-probe/run.py $(DERIVED_DATA)/mcp-write-disk-probe

TEST_TARGETS ?= TransitTests

.PHONY: test-quick
test-quick: prepare-cache-dirs test-create-task-project-schema-guard
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Debug \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(foreach target,$(TEST_TARGETS),-only-testing:$(target)) \
		$(PIPE_PRETTY)

.PHONY: test
test: prepare-cache-dirs test-create-task-project-schema-guard
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration Debug \
		$(XCODEBUILD_CACHE_FLAGS) \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

.PHONY: test-ui
test-ui: prepare-cache-dirs test-create-task-project-schema-guard
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration Debug \
		$(XCODEBUILD_CACHE_FLAGS) \
		-only-testing:TransitUITests \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

# Device deployment
DEVICE_MODEL ?= iPhone 17 Pro
DEVICE_ID = $(shell tmp=$$(mktemp); \
	xcrun devicectl list devices --json-output "$$tmp" >/dev/null 2>&1; \
	jq -r '.result.devices[] | select(.hardwareProperties.marketingName == "$(DEVICE_MODEL)") | .connectionProperties.potentialHostnames[] | select(startswith("0000"))' "$$tmp" 2>/dev/null | sed 's/.coredevice.local//' | head -1; \
	rm -f "$$tmp")

.PHONY: install
install: prepare-cache-dirs
	@if [ -z "$(DEVICE_ID)" ]; then \
		echo "Error: No $(DEVICE_MODEL) device found"; \
		exit 1; \
	fi
	@echo "Building $(CONFIG) for device $(DEVICE_ID)..."
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' \
		-configuration $(CONFIG) \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(PIPE_PRETTY)
	@echo "Installing on device..."
	xcrun devicectl device install app \
		--device $(DEVICE_ID) \
		$(DERIVED_DATA)/Build/Products/$(CONFIG)-iphoneos/Transit.app

.PHONY: run
run: install
	@echo "Launching app..."
	xcrun devicectl device process launch --device $(DEVICE_ID) $(BUNDLE_ID)

# Release builds — delegate to base targets with CONFIG=Release
.PHONY: install-release
install-release:
	$(MAKE) install CONFIG=Release

.PHONY: run-release
run-release:
	$(MAKE) run CONFIG=Release

.PHONY: build-macos-release
build-macos-release:
	$(MAKE) build-macos CONFIG=Release

.PHONY: run-macos-release
run-macos-release: build-macos-release
	@echo "Launching app..."
	open $(DERIVED_DATA)/Build/Products/Release/Transit.app

# Distribution
ARCHIVE_PATH = ./build/Transit.xcarchive
EXPORT_PATH = ./build/export

.PHONY: archive
archive: prepare-cache-dirs
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		$(XCODEBUILD_CACHE_FLAGS) \
		-allowProvisioningUpdates \
		$(PIPE_PRETTY)
	@echo "Archive created at $(ARCHIVE_PATH)"

# To re-upload an existing archive without rebuilding:
#   xcodebuild -exportArchive -archivePath ./build/Transit.xcarchive \
#     -exportOptionsPlist ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates
.PHONY: upload
upload: archive
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT_PATH) \
		-allowProvisioningUpdates
	@echo "Uploaded to App Store Connect"

# Cleaning
.PHONY: clean
clean: prepare-cache-dirs
	$(PIPEFAIL) $(XCODEBUILD_ENV) xcodebuild clean \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		$(XCODEBUILD_CACHE_FLAGS)
	rm -rf $(DERIVED_DATA) build
