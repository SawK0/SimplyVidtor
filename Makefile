PROJECT     := SimplyVidtor.xcodeproj
SCHEME      := SimplyVidtor
DESTINATION := platform=iOS Simulator,name=iPhone 17 Pro
XCB         := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'
SIMULATOR   := iPhone 17 Pro
BUNDLE_ID   := sawko.SimplyVidtor
ARGS        ?=

.PHONY: build test test-unit test-ui clean run gallery

build:
	$(XCB) build

test:
	$(XCB) test

test-unit:
	$(XCB) test -only-testing:SimplyVidtorTests

test-ui:
	$(XCB) test -only-testing:SimplyVidtorUITests

clean:
	$(XCB) clean

# Build Debug, boot the simulator, install and launch. Extra launch args: make run ARGS="-foo"
run: build
	@APP=$$($(XCB) -showBuildSettings 2>/dev/null | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/{print $$2}'); \
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true; \
	open -a Simulator; \
	xcrun simctl install '$(SIMULATOR)' "$$APP" && \
	xcrun simctl launch --terminate-running-process '$(SIMULATOR)' $(BUNDLE_ID) $(ARGS)

gallery:
	@$(MAKE) run ARGS=-componentGallery
