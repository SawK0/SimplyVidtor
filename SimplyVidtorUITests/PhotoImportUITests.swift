import XCTest

/// Drives the real photo picker. Needs the sample video and one photo in the
/// simulator's library, otherwise it skips:
///   xcrun simctl addmedia booted SimplyVidtorTests/Resources/sample-2s.mov <photo.jpg>
final class PhotoImportUITests: XCTestCase {
    @MainActor
    func testImportsVideoAndPhotoInSelectionOrder() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()
        app.buttons["projects.newProject"].tap()

        let onboardingOK = app.buttons["OK"]
        if onboardingOK.waitForExistence(timeout: 3) { onboardingOK.tap() }

        let video = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Video, two seconds'")).firstMatch
        guard video.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sample video not in the simulator's photo library")
        }
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        // Picker cells live in another process and report as not hittable; tap by coordinate.
        tapCenter(of: video)
        tapCenter(of: photo)

        let addButton = app.buttons["mediaPicker.add"]
        XCTAssertEqual(addButton.label, "Add 2 clips")
        addButton.tap()

        // New projects open with the format sheet; keep the default.
        let formatDone = app.buttons["format.done"]
        XCTAssertTrue(formatDone.waitForExistence(timeout: 15), "Editor did not open")
        formatDone.tap()

        // 2 s video + 3 s photo.
        let timecode = app.staticTexts["editor.timecode"]
        XCTAssertTrue(timecode.waitForExistence(timeout: 15), "Editor did not open")
        // The timecode shows 0 / 0 until the session has loaded.
        expectation(for: NSPredicate(format: "label == '00:00.0 / 00:05.0'"), evaluatedWith: timecode)
        waitForExpectations(timeout: 10)
        app.buttons["editor.close"].tap()
        XCTAssertTrue(app.buttons["projects.card.Untitled Project"].waitForExistence(timeout: 3))
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tapCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
