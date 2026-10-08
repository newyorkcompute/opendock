.PHONY: build run test format lint release release-native notarize dist clean

SWIFT_SOURCES = Sources App Tests

build:        ## Debug build + .app bundle
	scripts/build-app.sh --debug

run:          ## Build and launch
	scripts/run.sh

test:         ## Run unit tests
	swift test

format:       ## Format Swift sources in place (swift-format, per .swift-format)
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

lint:         ## Fail on formatting or lint warnings, as CI does
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

release:      ## Optimized universal (arm64 + x86_64) build + .app bundle
	scripts/build-app.sh

release-native: ## Optimized build for this Mac's architecture only
	scripts/build-app.sh --native

notarize:     ## Notarize + staple build/OpenDock.app (see RELEASING.md)
	scripts/notarize.sh build/OpenDock.app

dist:         ## Zip build/OpenDock.app + SHA-256 into build/dist
	scripts/package-app.sh

clean:
	rm -rf .build build
