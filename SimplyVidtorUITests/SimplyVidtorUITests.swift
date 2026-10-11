import XCTest

final class SimplyVidtorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-stubMediaPicker", "-seedSampleAudio"]
        app.launch()
    }

    @MainActor
    func testAppLaunchesToEmptyProjects() throws {
        XCTAssertTrue(app.buttons["projects.newProject"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your projects will appear here."].exists)
    }

    @MainActor
    func testNewProjectFlowReachesEditorAndExport() throws {
        createProject()

        let export = app.buttons["editor.export"]
        export.tap()

        let closeExport = app.buttons["export.close"]
        XCTAssertTrue(closeExport.waitForExistence(timeout: 3))
        closeExport.tap()
        XCTAssertTrue(closeExport.waitForNonExistence(timeout: 3))

        app.buttons["editor.close"].tap()
        XCTAssertTrue(app.buttons["projects.card.Untitled Project"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPlaybackAdvancesTimecode() throws {
        createProject()
        let timecode = app.staticTexts["editor.timecode"]
        XCTAssertTrue(timecode.waitForExistence(timeout: 3))
        XCTAssertEqual(timecode.label, "00:00.0 / 00:05.0")

        let playPause = app.buttons["editor.playPause"]
        playPause.tap()
        XCTAssertEqual(playPause.label, "Pause")
        let advanced = NSPredicate(format: "label != '00:00.0 / 00:05.0'")
        expectation(for: advanced, evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
        playPause.tap()
        XCTAssertEqual(playPause.label, "Play")
    }

    @MainActor
    func testSwipingTimelineScrubs() throws {
        createProject()
        XCTAssertTrue(app.otherElements["timeline.clip.0"].waitForExistence(timeout: 3)
            || app.images["timeline.clip.0"].exists
            || app.descendants(matching: .any)["timeline.clip.0"].exists)
        let timecode = app.staticTexts["editor.timecode"]
        XCTAssertEqual(timecode.label, "00:00.0 / 00:05.0")

        app.descendants(matching: .any)["editor.timeline"].swipeLeft()
        let moved = NSPredicate(format: "label != '00:00.0 / 00:05.0'")
        expectation(for: moved, evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testSelectClipAndTrimEnd() throws {
        createProject()
        // Zoom out so the clip's end handle is on screen.
        app.descendants(matching: .any)["editor.timeline"].pinch(withScale: 0.3, velocity: -1)
        sleep(1)
        let clip = app.descendants(matching: .any)["timeline.clip.0"]
        clip.tap()

        let trailing = app.descendants(matching: .any)["timeline.trim.trailing"]
        XCTAssertTrue(trailing.waitForExistence(timeout: 2), "Selecting a clip shows trim handles")

        let start = trailing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -60, dy: 0)))

        let timecode = app.staticTexts["editor.timecode"]
        let shorter = NSPredicate(format: "NOT (label ENDSWITH '/ 00:05.0')")
        expectation(for: shorter, evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testLongPressDragReordersClips() throws {
        createProject()
        let timeline = app.descendants(matching: .any)["editor.timeline"]
        XCTAssertTrue(app.descendants(matching: .any)["timeline.clip.0"].waitForExistence(timeout: 3))
        app.buttons["editor.addClip"].tap()
        app.buttons["mediaPicker.add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline.clip.1"].waitForExistence(timeout: 3))

        // Zoom out so both clips fit on screen.
        timeline.pinch(withScale: 0.3, velocity: -1)
        sleep(1)

        // Make the first clip distinguishable by trimming it, then deselect via the ruler.
        clip(0).tap()
        let trailing = app.descendants(matching: .any)["timeline.trim.trailing"]
        XCTAssertTrue(trailing.waitForExistence(timeout: 2))
        let handle = trailing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: -30, dy: 0)))
        let trimmedValue = try XCTUnwrap(clip(0).value as? String)
        XCTAssertNotEqual(trimmedValue, "Video, 5.0 seconds")
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
        XCTAssertTrue(trailing.waitForNonExistence(timeout: 2))

        // Long-press the middle of the first clip and drag it past the second.
        let grab = clip(0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let drop = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))
        grab.press(forDuration: 0.6, thenDragTo: drop)

        expectation(for: NSPredicate(format: "value == %@", trimmedValue), evaluatedWith: clip(1))
        waitForExpectations(timeout: 3)
        XCTAssertEqual(clip(0).value as? String, "Video, 5.0 seconds")
    }

    private func clip(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["timeline.clip.\(index)"]
    }

    @MainActor
    func testCancellingPickerStaysOnProjects() throws {
        app.buttons["projects.newProject"].tap()

        let close = app.buttons["mediaPicker.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()

        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["editor.export"].exists)
        XCTAssertTrue(app.staticTexts["Your projects will appear here."].exists)
    }

    @MainActor
    func testEditorAudioToolOpensPickerOnAudioTab() throws {
        createProject()

        app.buttons["editor.tool.audio"].tap()
        XCTAssertTrue(app.buttons["audio.importFiles"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testPreviewSelectAndAddAudio() throws {
        app.buttons["projects.newProject"].tap()
        app.buttons["Audio"].tap()

        let play = app.buttons["audio.play.Sample Tone"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertEqual(play.label, "Pause preview")
        play.tap()
        XCTAssertEqual(play.label, "Play preview")

        app.buttons["audio.row.Sample Tone"].tap()
        let add = app.buttons["mediaPicker.add"]
        XCTAssertEqual(add.label, "Add audio")
        add.tap()
        XCTAssertTrue(app.buttons["editor.export"].waitForExistence(timeout: 3), "Editor did not open")
    }

    @MainActor
    func testRenameDuplicateAndDeleteProject() throws {
        createProject()
        app.buttons["editor.close"].tap()

        // Rename
        openMenu(on: "Untitled Project")
        app.buttons["Rename"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Beach Day")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["projects.card.Beach Day"].waitForExistence(timeout: 3))

        // Duplicate
        openMenu(on: "Beach Day")
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(app.buttons["projects.card.Beach Day copy"].waitForExistence(timeout: 3))

        // Delete
        openMenu(on: "Beach Day copy")
        app.buttons["Delete"].tap()
        let confirm = app.buttons["Delete Project"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["projects.card.Beach Day copy"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["projects.card.Beach Day"].exists)
    }

    // MARK: - Helpers

    private func createProject() {
        app.buttons["projects.newProject"].tap()
        let add = app.buttons["mediaPicker.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.buttons["editor.export"].waitForExistence(timeout: 3), "Editor did not open")
        // Wait until the editor has settled; presenting a cover mid-transition is dropped.
        XCTAssertTrue(app.descendants(matching: .any)["timeline.clip.0"].waitForExistence(timeout: 5))
    }

    private func openMenu(on projectName: String) {
        let card = app.buttons["projects.card.\(projectName)"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.press(forDuration: 1)
    }
}
