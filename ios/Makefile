# Makefile — convenience targets for the sous-chef-ios iOS app.
#
# Depends on:     xcodegen, swift, xcodebuild, swiftformat, swiftlint on PATH.
#                 Install on macOS via Homebrew: brew install xcodegen
#                 swiftformat swiftlint. The Xcode toolchain ships swift and
#                 xcodebuild.
# Depended on by: developers and CI. A consistent entry point keeps Phase 4
#                 invocations identical across machines, the Conductor's
#                 reviewer harness, and any later CI host.
# Why it exists:  dc-06 ("Tool version drift") and dc-00 ("the codebase stands
#                 on its own") both want every common command to have one
#                 documented invocation. The Makefile is the contract.

SCHEME := SousChef
PROJECT := SousChef.xcodeproj
SIMULATOR := platform=iOS Simulator,name=iPhone 15
GENERIC := generic/platform=iOS Simulator

.PHONY: help gen build test test-package test-app lint fmt fmt-check clean

help: ## Show this help.
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

gen: ## Regenerate SousChef.xcodeproj from project.yml.
	xcodegen generate

build: gen ## Build the iOS app for the simulator.
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(GENERIC)' \
		build

test: test-package test-app ## Run the package tests and the app tests.

test-package: ## Run SousChefKit unit tests via swift test.
	cd SousChefKit && swift test

test-app: gen ## Run the app's xcodebuild test action.
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(SIMULATOR)' \
		test

lint: ## Run SwiftLint in strict mode over the ios subtree.
	swiftlint --strict

fmt: ## Apply SwiftFormat to the ios subtree.
	swiftformat .

fmt-check: ## Verify SwiftFormat would make no changes (CI gate).
	swiftformat --lint .

clean: ## Remove derived data and the generated Xcode project.
	rm -rf DerivedData .build .swiftpm $(PROJECT)
