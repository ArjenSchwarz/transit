# Transit Makefile

SCHEME = Transit
PROJECT = Transit/Transit.xcodeproj

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  lint        - Run SwiftLint"
	@echo "  lint-fix    - Run SwiftLint with auto-fix"
	@echo "  build-ios   - Build for iOS Simulator"
	@echo "  build-macos - Build for macOS"
	@echo "  build       - Build for both platforms"
	@echo "  test-quick  - Run unit tests on macOS (fast, no simulator)"
	@echo "  test        - Run full test suite on iOS Simulator"
	@echo "  test-ui     - Run UI tests only"
	@echo "  install     - Build and install on physical device"
	@echo "  run         - Build, install, and launch on physical device"
	@echo "  clean       - Clean build artifacts"
	@echo ""
	@echo "Device deployment uses DEVICE_MODEL (default: iPhone 17 Pro)"
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
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify || xcodebuild build \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'platform=iOS Simulator,name=iPhone 17' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA)

.PHONY: build-macos
build-macos: clean
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify || xcodebuild build \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'platform=macOS' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA)

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
		| xcbeautify || xcodebuild test \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'platform=macOS' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA) \
			-only-testing:TransitTests

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
		| xcbeautify || xcodebuild test \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'platform=iOS Simulator,name=iPhone 17' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA) \
			-parallel-testing-worker-count 1 \
			-maximum-concurrent-test-simulator-destinations 1

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
		| xcbeautify || xcodebuild test \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'platform=iOS Simulator,name=iPhone 17' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA) \
			-only-testing:TransitUITests \
			-parallel-testing-worker-count 1 \
			-maximum-concurrent-test-simulator-destinations 1

# Device deployment
DEVICE_MODEL ?= iPhone 17 Pro
DEVICE_JSON := $(shell mktemp)
DEVICE_ID = $(shell xcrun devicectl list devices --json-output $(DEVICE_JSON) >/dev/null 2>&1; \
	jq -r '.result.devices[] | select(.hardwareProperties.marketingName == "$(DEVICE_MODEL)") | .connectionProperties.potentialHostnames[] | select(startswith("0000"))' $(DEVICE_JSON) 2>/dev/null | sed 's/.coredevice.local//' | head -1; \
	rm -f $(DEVICE_JSON))

.PHONY: install
install:
	@if [ -z "$(DEVICE_ID)" ]; then \
		echo "Error: No $(DEVICE_MODEL) device found"; \
		exit 1; \
	fi
	@echo "Building for device $(DEVICE_ID)..."
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'id=$(DEVICE_ID)' \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		| xcbeautify || xcodebuild build \
			-project $(PROJECT) \
			-scheme $(SCHEME) \
			-destination 'id=$(DEVICE_ID)' \
			-configuration Debug \
			-derivedDataPath $(DERIVED_DATA)
	@echo "Installing on device..."
	xcrun devicectl device install app \
		--device $(DEVICE_ID) \
		$(DERIVED_DATA)/Build/Products/Debug-iphoneos/Transit.app

.PHONY: run
run: install
	@echo "Launching app..."
	xcrun devicectl device process launch --device $(DEVICE_ID) me.nore.ig.Transit

# Cleaning
.PHONY: clean
clean:
	xcodebuild clean \
		-project $(PROJECT) \
		-scheme $(SCHEME)
	rm -rf DerivedData
