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
.PHONY: lint
lint:
	swiftlint lint --strict

.PHONY: lint-fix
lint-fix:
	swiftlint lint --fix --strict

# Building
DERIVED_DATA = ./DerivedData

.PHONY: build-ios
build-ios:
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
		$(PIPE_PRETTY)

.PHONY: build-macos
build-macos: clean
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
		$(PIPE_PRETTY)

.PHONY: build
build: build-ios build-macos

# Testing
.PHONY: test-quick
test-quick:
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:TransitTests \
		$(PIPE_PRETTY)

.PHONY: test
test:
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		-parallel-testing-worker-count 1 \
		-maximum-concurrent-test-simulator-destinations 1 \
		$(PIPE_PRETTY)

.PHONY: test-ui
test-ui:
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=iPhone 17' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
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
install:
	@if [ -z "$(DEVICE_ID)" ]; then \
		echo "Error: No $(DEVICE_MODEL) device found"; \
		exit 1; \
	fi
	@echo "Building $(CONFIG) for device $(DEVICE_ID)..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
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
archive:
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'generic/platform=iOS' \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		-allowProvisioningUpdates \
		$(PIPE_PRETTY)
	@echo "Archive created at $(ARCHIVE_PATH)"

# To re-upload an existing archive without rebuilding:
#   xcodebuild -exportArchive -archivePath ./build/Transit.xcarchive \
#     -exportOptionsPlist ExportOptions.plist -exportPath ./build/export -allowProvisioningUpdates
.PHONY: upload
upload: archive
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT_PATH) \
		-allowProvisioningUpdates
	@echo "Uploaded to App Store Connect"

# Cleaning
.PHONY: clean
clean:
	xcodebuild clean \
		-project $(PROJECT) \
		-scheme $(SCHEME)
	rm -rf $(DERIVED_DATA) build
