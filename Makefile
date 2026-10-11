PROJECT     := SimplyVidtor.xcodeproj
SCHEME      := SimplyVidtor
DESTINATION := platform=iOS Simulator,name=iPhone 17 Pro
XCB         := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)'

.PHONY: build test test-unit test-ui clean

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
