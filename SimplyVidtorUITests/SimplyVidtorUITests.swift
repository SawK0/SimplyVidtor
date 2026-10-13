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
    func testExportCanBeCancelledAndCompleted() throws {
        createProject()
        app.buttons["editor.export"].tap()
        let start = app.buttons["export.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["export.estimate"].label.hasPrefix("About"))

        // 4K takes long enough to cancel.
        app.descendants(matching: .any)["export.resolution"].buttons["4K"].tap()
        start.tap()
        let cancel = app.buttons["export.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Cancelling returns to settings")

        app.descendants(matching: .any)["export.resolution"].buttons["720p"].tap()
        start.tap()
        XCTAssertTrue(app.staticTexts["export.done"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["export.share"].exists)

        let save = app.buttons["export.save"]
        save.tap()
        // The add-only photos prompt appears the first time.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        expectation(for: NSPredicate(format: "label == 'Saved to Photos'"), evaluatedWith: save)
        waitForExpectations(timeout: 10)

        app.buttons["export.finish"].tap()
        XCTAssertTrue(app.buttons["editor.export"].waitForExistence(timeout: 3))
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
    func testSplitAtPlayhead() throws {
        createProject()
        let split = app.buttons["editor.tool.split"]
        XCTAssertFalse(split.isEnabled, "Can't split at the very start")

        let timeline = app.descendants(matching: .any)["editor.timeline"]
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.15))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -60, dy: 0)))
        XCTAssertTrue(split.waitForEnabled(timeout: 3))
        split.tap()
        XCTAssertTrue(clip(1).waitForExistence(timeout: 3))
    }

    @MainActor
    func testSpeedPanelChangesClipLength() throws {
        createProject()
        app.buttons["editor.tool.speed"].tap()

        let slider = app.descendants(matching: .any)["editor.speed.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 2), "Speed selects the clip under the playhead")
        XCTAssertEqual(app.staticTexts["editor.speed.value"].label, "1.0×")
        // 1× sits mid-track; drag the thumb right toward 3×.
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))

        let timecode = app.staticTexts["editor.timecode"]
        let shorter = NSPredicate(format: "NOT (label ENDSWITH '/ 00:05.0')")
        expectation(for: shorter, evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
        XCTAssertNotEqual(app.staticTexts["editor.speed.value"].label, "1.0×")

        app.buttons["editor.panel.done"].tap()
        XCTAssertTrue(app.buttons["editor.tool.speed"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testVolumePanelMutesClip() throws {
        createProject()
        app.buttons["editor.tool.volume"].tap()

        let value = app.staticTexts["editor.volume.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        XCTAssertEqual(value.label, "100%")
        let slider = app.descendants(matching: .any)["editor.volume.slider"]
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "label != '100%'"), evaluatedWith: value)
        waitForExpectations(timeout: 3)

        app.switches["editor.volume.mute"].switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: slider)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testFiltersPanelAppliesPresetToAll() throws {
        createProject()
        app.buttons["editor.addClip"].tap()
        app.buttons["mediaPicker.add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline.clip.1"].waitForExistence(timeout: 3))

        app.buttons["editor.tool.filters"].tap()
        let noir = app.buttons["editor.filter.noir"]
        XCTAssertTrue(noir.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["editor.filter.applyAll"].isEnabled, "Clips already match")
        noir.tap()

        XCTAssertTrue(app.descendants(matching: .any)["editor.filter.intensity"].waitForExistence(timeout: 2))
        XCTAssertTrue(noir.isSelected)
        let applyAll = app.buttons["editor.filter.applyAll"]
        XCTAssertTrue(applyAll.waitForEnabled(timeout: 2))
        applyAll.tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: applyAll)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testAdjustPanelChangesAndResets() throws {
        createProject()
        app.buttons["editor.tool.adjust"].tap()

        let value = app.staticTexts["editor.adjust.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        app.buttons["editor.adjust.warmth"].tap()
        let slider = app.descendants(matching: .any)["editor.adjust.slider"]
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '+'"), evaluatedWith: value)
        waitForExpectations(timeout: 3)

        app.buttons["editor.adjust.reset"].tap()
        expectation(for: NSPredicate(format: "label == '0'"), evaluatedWith: value)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testCropPanelRotatesAndCrops() throws {
        createProject()
        // Crop is past the right edge of the scrolling toolbar.
        app.buttons["editor.tool.adjust"].swipeLeft()
        app.buttons["editor.tool.crop"].tap()

        let reset = app.buttons["editor.crop.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        XCTAssertFalse(reset.isEnabled)
        app.buttons["editor.crop.rotate"].tap()
        XCTAssertTrue(reset.waitForEnabled(timeout: 2), "Rotating can be reset")
        reset.tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: reset)
        waitForExpectations(timeout: 3)

        app.buttons["editor.crop.edit"].tap()
        XCTAssertTrue(app.buttons["crop.done"].waitForExistence(timeout: 2))
        // The stub clip has no file, so the editor shows a square placeholder.
        app.descendants(matching: .any)["crop.ratio"].buttons["9:16"].tap()
        app.buttons["crop.done"].tap()
        XCTAssertTrue(reset.waitForEnabled(timeout: 3), "A 9:16 crop was saved")
    }

    @MainActor
    func testTransitionBetweenClipsShortensTimeline() throws {
        createProject()
        app.buttons["editor.addClip"].tap()
        app.buttons["mediaPicker.add"].tap()
        let cut = app.buttons["timeline.transition.0"]
        XCTAssertTrue(cut.waitForExistence(timeout: 3))
        let timecode = app.staticTexts["editor.timecode"]
        XCTAssertTrue(timecode.label.hasSuffix("/ 00:10.0"))

        cut.tap()
        let kind = app.descendants(matching: .any)["editor.transition.kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 2))
        kind.buttons["Cross-fade"].tap()
        expectation(for: NSPredicate(format: "label ENDSWITH '/ 00:09.5'"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)

        app.buttons["editor.panel.done"].tap()
        XCTAssertTrue(app.buttons["editor.tool.split"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testFullscreenPreviewPlaysAndCloses() throws {
        createProject()
        app.buttons["editor.fullscreen"].tap()
        let playPause = app.buttons["fullscreen.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 3))
        playPause.tap()
        XCTAssertEqual(playPause.label, "Pause")

        // Controls hide while playing; a tap brings them back.
        XCTAssertTrue(playPause.waitForNonExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["fullscreen.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 2))
        close.tap()
        XCTAssertTrue(app.buttons["editor.fullscreen"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAddEditAndDeleteText() throws {
        createProject()
        app.buttons["editor.tool.adjust"].swipeLeft()
        app.buttons["editor.tool.text"].tap()

        let field = app.textFields["editor.text.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Hello\n")
        XCTAssertTrue(app.staticTexts["Add Text"].exists, "Still new after typing")
        XCTAssertTrue(app.descendants(matching: .any)["editor.text.font"].waitForExistence(timeout: 2), "Style controls show once typing ends")
        app.buttons["editor.text.color.1"].tap()
        app.buttons["editor.panel.done"].tap()

        let text = app.descendants(matching: .any)["timeline.text.0"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        XCTAssertEqual(text.value as? String, "Hello")

        text.tap()
        XCTAssertEqual(app.textFields["editor.text.field"].value as? String, "Hello")
        app.buttons["editor.text.delete"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testTextCanBeMovedOnPreviewAndTrimmedOnTimeline() throws {
        createProject()
        app.buttons["editor.tool.adjust"].swipeLeft()
        app.buttons["editor.tool.text"].tap()
        let field = app.textFields["editor.text.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Drag me\n")

        let selection = app.descendants(matching: .any)["preview.textSelection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 2))
        XCTAssertEqual(selection.value as? String, "Drag me, 50% across, 50% down")
        // New text sits in the middle of the frame, which is centred in the preview.
        let start = selection.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -30)))
        let moved = NSPredicate(format: "NOT (value ENDSWITH '50% down')")
        expectation(for: moved, evaluatedWith: selection)
        waitForExpectations(timeout: 3)

        let text = app.descendants(matching: .any)["timeline.text.0"]
        let trailing = app.descendants(matching: .any)["timeline.trim.trailing"]
        XCTAssertTrue(trailing.waitForExistence(timeout: 2))
        let widthBefore = text.frame.width
        let handle = trailing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.2, thenDragTo: handle.withOffset(CGVector(dx: -60, dy: 0)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertLessThan(text.frame.width, widthBefore - 30, "Text was trimmed")

        app.buttons["editor.panel.done"].tap()
        XCTAssertTrue(app.buttons["editor.undo"].waitForEnabled(timeout: 2))
    }

    @MainActor
    func testAddSwapAndDeleteSticker() throws {
        createProject()
        app.buttons["editor.tool.adjust"].swipeLeft()
        app.buttons["editor.tool.sticker"].tap()
        let fire = app.buttons["editor.sticker.11"]
        XCTAssertTrue(fire.waitForExistence(timeout: 2))
        fire.tap()

        let item = app.descendants(matching: .any)["timeline.text.0"]
        XCTAssertTrue(item.waitForExistence(timeout: 2))
        XCTAssertEqual(item.value as? String, "🔥")
        app.buttons["editor.sticker.12"].tap()
        expectation(for: NSPredicate(format: "value == '❤️'"), evaluatedWith: item)
        waitForExpectations(timeout: 2)
        app.buttons["editor.panel.done"].tap()
        XCTAssertTrue(app.buttons["editor.undo"].waitForEnabled(timeout: 2))

        item.tap()
        let delete = app.buttons["editor.sticker.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2), "Tapping a sticker opens the sticker panel")
        delete.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testEditAndDeleteAudioItem() throws {
        createProject()
        app.buttons["editor.tool.adjust"].swipeLeft()
        app.buttons["editor.tool.audio"].tap()
        let row = app.buttons["audio.row.Sample Tone"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["mediaPicker.add"].tap()

        let item = app.descendants(matching: .any)["timeline.audio.0"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
        let fadeIn = app.descendants(matching: .any)["editor.audio.fadeIn"]
        XCTAssertTrue(fadeIn.waitForExistence(timeout: 2), "Tapping audio opens its panel")
        fadeIn.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.undo"].waitForEnabled(timeout: 2))

        let trailing = app.descendants(matching: .any)["timeline.trim.trailing"]
        XCTAssertTrue(trailing.exists)
        let before = try XCTUnwrap(item.value as? String)
        let handle = trailing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.2, thenDragTo: handle.withOffset(CGVector(dx: -40, dy: 0)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        expectation(for: NSPredicate(format: "value != %@", before), evaluatedWith: item)
        waitForExpectations(timeout: 3)

        app.buttons["editor.audio.delete"].tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: 3))
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
        // Audio is past the right edge of the scrolling toolbar.
        app.buttons["editor.tool.adjust"].swipeLeft()
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

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
