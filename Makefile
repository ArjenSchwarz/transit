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

.PHONY: lint
lint:
	swiftlint lint --strict --cache-path $(SWIFTLINT_CACHE)

.PHONY: lint-fix
lint-fix:
	swiftlint lint --fix --strict --cache-path $(SWIFTLINT_CACHE)

# Building
DERIVED_DATA = ./DerivedData

# Workspace-local cache locations. Xcode and its subprocesses (SwiftPM, Clang)
# otherwise scatter caches across ~/Library/Caches and ~/.cache, which fail in
# sandboxed/dev environments. Keep everything under DerivedData so a single
# `make clean` is enough. See T-1241.
SPM_CACHE        = $(DERIVED_DATA)/SourcePackages/cache
SPM_CLONED       = $(DERIVED_DATA)/SourcePackages/checkouts
WORKSPACE_CACHE  = $(DERIVED_DATA)/Caches
WORKSPACE_TMP    = $(DERIVED_DATA)/tmp
CLANG_MODULE_CACHE = $(DERIVED_DATA)/ModuleCache.noindex

XCODEBUILD_CACHE_FLAGS = \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(SPM_CLONED) \
	-packageCachePath $(SPM_CACHE)

# Exported before every xcodebuild call so SwiftPM resolution, Clang module
# cache fallbacks ($XDG_CACHE_HOME/clang/ModuleCache), and compiler temp
# diagnostics (.dia) all stay inside the workspace.
XCODEBUILD_ENV = \
	XDG_CACHE_HOME=$(abspath $(WORKSPACE_CACHE)) \
	TMPDIR=$(abspath $(WORKSPACE_TMP)) \
	CLANG_MODULE_CACHE_PATH=$(abspath $(CLANG_MODULE_CACHE))

.PHONY: prepare-cache-dirs
prepare-cache-dirs:
	@mkdir -p $(SPM_CACHE) $(SPM_CLONED) $(WORKSPACE_CACHE) $(WORKSPACE_TMP) $(CLANG_MODULE_CACHE)

.PHONY: build-ios
build-ios: prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration $(CONFIG) \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(PIPE_PRETTY)

.PHONY: build-macos
build-macos: clean prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration $(CONFIG) \
		$(XCODEBUILD_CACHE_FLAGS) \
		$(PIPE_PRETTY)

.PHONY: build
build: build-ios build-macos

# Testing
.PHONY: test-quick
test-quick: prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Debug \
		$(XCODEBUILD_CACHE_FLAGS) \
		-only-testing:TransitTests \
		$(PIPE_PRETTY)

.PHONY: test
test: prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration Debug \
		$(XCODEBUILD_CACHE_FLAGS) \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

.PHONY: test-ui
test-ui: prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild test \
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
	$(XCODEBUILD_ENV) xcodebuild build \
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
	$(XCODEBUILD_ENV) xcodebuild archive \
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
	$(XCODEBUILD_ENV) xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT_PATH) \
		-allowProvisioningUpdates
	@echo "Uploaded to App Store Connect"

# Cleaning
.PHONY: clean
clean: prepare-cache-dirs
	$(XCODEBUILD_ENV) xcodebuild clean \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		$(XCODEBUILD_CACHE_FLAGS)
	rm -rf $(DERIVED_DATA) build
