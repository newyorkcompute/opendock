.PHONY: build run test release clean

build:        ## Debug build + .app bundle
	scripts/build-app.sh --debug

run:          ## Build and launch
	scripts/run.sh

test:         ## Run unit tests
	swift test

release:      ## Optimized build + .app bundle
	scripts/build-app.sh

clean:
	rm -rf .build build
