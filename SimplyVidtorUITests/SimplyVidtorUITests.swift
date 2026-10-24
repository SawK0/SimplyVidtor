import XCTest

final class SimplyVidtorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-stubMediaPicker", "-seedSampleAudio", "-seedMotionPack"]
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
        XCTAssertFalse(app.switches["export.smartHDR"].isEnabled, "No HDR clips in a stub project")

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

        // Make the first clip distinguishable by trimming it, then deselect by tapping
        // the empty audio row (ruler taps move the playhead and keep the selection).
        clip(0).tap()
        let trailing = app.descendants(matching: .any)["timeline.trim.trailing"]
        XCTAssertTrue(trailing.waitForExistence(timeout: 2))
        let handle = trailing.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: -30, dy: 0)))
        let trimmedValue = try XCTUnwrap(clip(0).value as? String)
        XCTAssertNotEqual(trimmedValue, "Video, 5.0 seconds")
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.88)).tap()
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
        tapTool("editor.tool.crop")

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
        let undo = app.buttons["editor.undo"]
        let barBefore = undo.frame.minY
        tapTool("editor.tool.text")

        let field = app.textFields["editor.text.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        // The timeline hides while typing, so the preview grows down into its space.
        expectation(for: NSPredicate { _, _ in undo.frame.minY > barBefore + 50 }, evaluatedWith: nil)
        waitForExpectations(timeout: 2)
        let barWhileTyping = undo.frame.minY
        field.typeText("Hello\n")
        // It comes back once typing ends.
        expectation(for: NSPredicate { _, _ in undo.frame.minY < barWhileTyping - 50 }, evaluatedWith: nil)
        waitForExpectations(timeout: 2)
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
    func testOverlappingTextGetsItsOwnTrack() throws {
        createProject()
        for text in ["One", "Two"] {
            tapTool("editor.tool.text")
            let field = app.textFields["editor.text.field"]
            XCTAssertTrue(field.waitForExistence(timeout: 2))
            field.typeText("\(text)\n")
            app.buttons["editor.panel.done"].tap()
        }
        let second = app.descendants(matching: .any)["timeline.track.text.1"]
        XCTAssertTrue(second.waitForExistence(timeout: 3), "Both start at the playhead, so the second gets a new track")
        let one = app.descendants(matching: .any)["timeline.text.0"].frame
        let two = app.descendants(matching: .any)["timeline.text.1"].frame
        XCTAssertLessThan(two.maxY, one.minY + 1, "Drawn on top, so shown on the row above")
    }

    @MainActor
    func testAddOverlayClipAndEditIt() throws {
        createProject()
        tapTool("editor.tool.overlay")
        let add = app.buttons["mediaPicker.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        let overlay = app.descendants(matching: .any)["timeline.overlay.0"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["timeline.track.video.0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["timeline.clip.1"].exists, "Not added to the main track")
        XCTAssertTrue(overlay.isSelected, "The new overlay is selected")

        // Clip tools act on the selected overlay.
        tapTool("editor.tool.transform")
        let reset = app.buttons["editor.transform.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        XCTAssertTrue(reset.isEnabled, "Overlays start smaller than the frame")
        app.buttons["editor.panel.done"].tap()

        tapTool("editor.tool.delete")
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testMovingAClipLeavesAGapAndSnapsBack() throws {
        createProject()
        // Long press the clip and drag it right: it leaves a gap at the start.
        let clip = app.descendants(matching: .any)["timeline.clip.0"]
        XCTAssertTrue(clip.waitForExistence(timeout: 3))
        let before = clip.frame.minX
        let grab = clip.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        grab.press(forDuration: 0.6, thenDragTo: grab.withOffset(CGVector(dx: 80, dy: 0)))
        let timecode = app.staticTexts["editor.timecode"]
        expectation(for: NSPredicate(format: "NOT (label ENDSWITH '/ 00:05.0')"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
        let moved = clip.frame.minX - before
        XCTAssertGreaterThan(moved, 40)

        // Dragging it back to just short of the start snaps it there.
        let regrab = clip.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        regrab.press(forDuration: 0.6, thenDragTo: regrab.withOffset(CGVector(dx: -(moved - 5), dy: 0)))
        expectation(for: NSPredicate(format: "label ENDSWITH '/ 00:05.0'"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testManyOverlappingVideosShowAWarning() throws {
        createProject()
        let warning = app.buttons["editor.videoLoadWarning"]
        for count in 1...4 {
            XCTAssertFalse(warning.exists, "Fine with \(count) videos")
            tapTool("editor.tool.overlay")
            let add = app.buttons["mediaPicker.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 3))
            add.tap()
            XCTAssertTrue(app.descendants(matching: .any)["timeline.overlay.\(count - 1)"].waitForExistence(timeout: 3))
        }
        XCTAssertTrue(warning.waitForExistence(timeout: 2), "Five videos play at once")
        warning.tap()
        let show = app.buttons["Show Me"]
        XCTAssertTrue(show.waitForExistence(timeout: 2))
        show.tap()
    }

    @MainActor
    func testDragClipsBetweenMainAndVideoTracks() throws {
        createProject()
        app.buttons["editor.addClip"].tap()
        app.buttons["mediaPicker.add"].tap()
        XCTAssertTrue(clip(1).waitForExistence(timeout: 3))
        tapTool("editor.tool.track")
        app.buttons["Video Track"].tap()
        let row = app.descendants(matching: .any)["timeline.track.video.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        // Long press the first clip and drag it up onto the video track.
        let grab = clip(0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let above = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: clip(0).frame.midX, dy: row.frame.midY))
        XCTAssertLessThan(row.frame.midY, clip(0).frame.midY, "Video tracks sit above the main track")
        grab.press(forDuration: 0.6, thenDragTo: above, withVelocity: .slow, thenHoldForDuration: 0.2)
        let overlay = app.descendants(matching: .any)["timeline.overlay.0"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3), "Moved onto the video track")
        XCTAssertFalse(clip(1).exists, "One clip left on the main track")

        // Select it and drag it back down onto the main track.
        overlay.tap()
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let main = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: overlay.frame.midX, dy: clip(0).frame.midY))
        start.press(forDuration: 0.1, thenDragTo: main, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 3), "Back on the main track")
        XCTAssertTrue(clip(1).exists)
    }

    @MainActor
    func testAddMediaToAChosenVideoTrack() throws {
        createProject()
        for _ in 0..<2 {
            tapTool("editor.tool.track")
            app.buttons["Video Track"].tap()
        }
        let second = app.descendants(matching: .any)["timeline.track.video.1"]
        XCTAssertTrue(second.waitForExistence(timeout: 3))

        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: timeline.midX + 100, dy: second.frame.midY))
            .press(forDuration: 1)
        let here = app.buttons["Add Media Here"]
        XCTAssertTrue(here.waitForExistence(timeout: 2))
        here.tap()
        app.buttons["mediaPicker.add"].tap()

        let overlay = app.descendants(matching: .any)["timeline.overlay.0"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertEqual(overlay.frame.midY, second.frame.midY, accuracy: 4, "On the track that was long-pressed")
    }

    @MainActor
    func testFastDragMovesTheSelectedOverlay() throws {
        createProject()
        tapTool("editor.tool.overlay")
        let add = app.buttons["mediaPicker.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let overlay = app.descendants(matching: .any)["timeline.overlay.0"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertTrue(overlay.isSelected)

        // A quick flick with no pause: it moves the overlay, not the timeline.
        let before = overlay.frame.minX - clip(0).frame.minX
        // Near its left end: the overlay runs off screen, and the drag must stay on it.
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0, thenDragTo: start.withOffset(CGVector(dx: 80, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        let moved = overlay.frame.minX - clip(0).frame.minX
        XCTAssertGreaterThan(moved - before, 40, "The overlay moved along the main track")
    }

    @MainActor
    func testAddAndDeleteTrack() throws {
        createProject()
        tapTool("editor.tool.track")
        let video = app.buttons["Video Track"]
        XCTAssertTrue(video.waitForExistence(timeout: 2))
        video.tap()
        let row = app.descendants(matching: .any)["timeline.track.video.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        // Long press an empty part of the row, right of the playhead.
        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: timeline.midX + 100, dy: row.frame.midY))
            .press(forDuration: 1)
        let delete = app.buttons["Delete Track"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testTextCanBeMovedOnPreviewAndTrimmedOnTimeline() throws {
        createProject()
        tapTool("editor.tool.text")
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
        tapTool("editor.tool.sticker")
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
    func testAnimateSticker() throws {
        createProject()
        tapTool("editor.tool.sticker")
        let fire = app.buttons["editor.sticker.11"]
        XCTAssertTrue(fire.waitForExistence(timeout: 2))
        fire.tap()
        app.buttons["editor.animate"].tap()

        let pop = app.buttons["editor.motion.preset.builtin.pop"]
        XCTAssertTrue(pop.waitForExistence(timeout: 2))
        pop.tap()
        XCTAssertTrue(pop.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["editor.motion.duration"].exists)

        // Loops are listed separately.
        app.buttons["Loop"].tap()
        XCTAssertFalse(pop.exists)
        app.buttons["editor.motion.preset.builtin.pulse"].tap()

        // Done returns to the sticker panel, then commits.
        app.buttons["editor.panel.done"].tap()
        XCTAssertTrue(app.buttons["editor.sticker.delete"].waitForExistence(timeout: 2))
        app.buttons["editor.panel.done"].tap()
        let item = app.descendants(matching: .any)["timeline.text.0"]
        XCTAssertTrue(item.label.hasSuffix("animated"), "Got \(item.label)")
        XCTAssertTrue(app.buttons["editor.undo"].waitForEnabled(timeout: 2))
    }

    @MainActor
    func testImportedPackAnimatesTextAndCanBeRemoved() throws {
        createProject()
        tapTool("editor.tool.text")
        let field = app.textFields["editor.text.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Hi\n")
        app.buttons["editor.animate"].tap()

        // -seedMotionPack imports the bundled sample pack.
        let drop = app.buttons["editor.motion.preset.com.simplyvidtor.sample.drop"]
        XCTAssertTrue(drop.waitForExistence(timeout: 2))
        drop.tap()
        XCTAssertTrue(drop.isSelected)

        // Removing the pack keeps the animation on the text.
        let pack = app.descendants(matching: .any)["editor.motion.pack.com.simplyvidtor.sample"]
        pack.press(forDuration: 1)
        let remove = app.buttons["Remove Pack"]
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        remove.tap()
        XCTAssertTrue(pack.waitForNonExistence(timeout: 2))
        XCTAssertTrue(drop.exists && drop.isSelected, "Still shown as the text's animation")
        XCTAssertFalse(app.buttons["editor.motion.preset.com.simplyvidtor.sample.swing"].exists)
    }

    @MainActor
    func testPaidPackIsLocked() throws {
        createProject()
        tapTool("editor.tool.sticker")
        let fire = app.buttons["editor.sticker.11"]
        XCTAssertTrue(fire.waitForExistence(timeout: 2))
        fire.tap()
        app.buttons["editor.animate"].tap()

        // -seedMotionPack also adds a paid copy of the sample pack.
        let drop = app.buttons["editor.motion.preset.com.simplyvidtor.sample-pro.drop"]
        XCTAssertTrue(drop.waitForExistence(timeout: 2))
        XCTAssertEqual(drop.value as? String, "Locked")
        drop.tap()
        let ok = app.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 2), "Explains the pack is paid")
        ok.tap()
        XCTAssertFalse(drop.isSelected)
        XCTAssertTrue(app.buttons["editor.motion.none"].isSelected)
    }

    @MainActor
    func testEditAndDeleteAudioItem() throws {
        createProject()
        tapTool("editor.tool.audio")
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
    func testLongAudioKeepsOtherTracksVisible() throws {
        createProject()
        tapTool("editor.tool.audio")
        let row = app.buttons["audio.row.Long Tone"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["mediaPicker.add"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["timeline.audio.0"].waitForExistence(timeout: 3))

        // The clip starts at the playhead, in the middle of the timeline.
        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        let clip = app.descendants(matching: .any)["timeline.clip.0"].frame
        XCTAssertEqual(clip.minX, timeline.midX, accuracy: 4, "Clip row was pushed off screen")
        // The project runs to the song's end.
        let timecode = app.staticTexts["editor.timecode"].label
        XCTAssertTrue(timecode.hasSuffix("/ 01:00.0"), "Got \(timecode)")
    }

    @MainActor
    func testFormatSheetChangesFrameAndReopens() throws {
        app.buttons["projects.newProject"].tap()
        app.buttons["mediaPicker.add"].tap()
        let summary = app.staticTexts["format.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "New project opens with its format")

        app.buttons["format.shape.square"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '1080 × 1080'"), evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        app.descendants(matching: .any)["format.frameRate"].buttons["24 fps"].tap()
        expectation(for: NSPredicate(format: "label ENDSWITH '24 fps'"), evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        app.buttons["format.done"].tap()

        app.buttons["editor.format"].tap()
        XCTAssertTrue(app.buttons["format.shape.square"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["format.shape.square"].isSelected, "The choice was saved")
        XCTAssertTrue(app.buttons["editor.undo"].isEnabled)
    }

    @MainActor
    func testTransformPanelAndPreviewGestures() throws {
        createProject()
        tapTool("editor.tool.transform")
        let reset = app.buttons["editor.transform.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        XCTAssertFalse(reset.isEnabled)

        app.descendants(matching: .any)["editor.transform.mode"].buttons["Fill"].tap()
        XCTAssertTrue(reset.waitForEnabled(timeout: 2))
        reset.tap()
        expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: reset)
        waitForExpectations(timeout: 3)

        // Dragging on the preview moves the selected clip.
        let preview = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        preview.press(forDuration: 0.1, thenDragTo: preview.withOffset(CGVector(dx: 60, dy: 0)),
                      withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(reset.waitForEnabled(timeout: 3), "The clip moved")
    }

    @MainActor
    func testTransformKeyframesMakeAZoom() throws {
        createProject()
        tapTool("editor.tool.transform")
        let toggle = app.buttons["editor.keyframe.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()
        let clip = app.descendants(matching: .any)["timeline.clip.0"]
        expectation(for: NSPredicate(format: "value ENDSWITH '1 keyframes'"), evaluatedWith: clip)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(toggle.isSelected, "The playhead is on the new keyframe")

        // Later in the clip, changing the scale adds a second keyframe.
        let ruler = app.descendants(matching: .any)["timeline.ruler"].firstMatch
        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: timeline.midX + 120, dy: ruler.frame.midY))
            .tap()
        let timecode = app.staticTexts["editor.timecode"]
        expectation(for: NSPredicate(format: "NOT (label BEGINSWITH '00:00.0')"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(toggle.isSelected)
        let scale = app.descendants(matching: .any)["editor.transform.scale"]
        let thumb = scale.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: thumb.withOffset(CGVector(dx: 40, dy: 0)))
        expectation(for: NSPredicate(format: "value ENDSWITH '2 keyframes'"), evaluatedWith: clip)
        waitForExpectations(timeout: 3)

        // Previous jumps back to the first keyframe.
        app.buttons["editor.keyframe.previous"].tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH '00:00.0'"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["editor.keyframe.easing"].waitForExistence(timeout: 2), "Easing to the next keyframe")
    }

    @MainActor
    func testStickerKeyframes() throws {
        createProject()
        tapTool("editor.tool.sticker")
        let fire = app.buttons["editor.sticker.11"]
        XCTAssertTrue(fire.waitForExistence(timeout: 2))
        fire.tap()
        let toggle = app.buttons["editor.keyframe.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()
        XCTAssertTrue(toggle.isSelected)

        // Later, resizing adds a second keyframe.
        let ruler = app.descendants(matching: .any)["timeline.ruler"].firstMatch
        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: timeline.midX + 80, dy: ruler.frame.midY))
            .tap()
        expectation(for: NSPredicate(format: "isSelected == false"), evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        let size = app.descendants(matching: .any)["editor.sticker.size"]
        let thumb = size.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        thumb.press(forDuration: 0.05, thenDragTo: thumb.withOffset(CGVector(dx: 50, dy: 0)))

        app.buttons["editor.panel.done"].tap()
        let item = app.descendants(matching: .any)["timeline.text.0"]
        XCTAssertTrue(item.label.hasSuffix("2 keyframes"), "Got \(item.label)")
    }

    @MainActor
    func testTappingRulerMovesPlayhead() throws {
        createProject()
        let timecode = app.staticTexts["editor.timecode"]
        XCTAssertEqual(timecode.label, "00:00.0 / 00:05.0")
        // Right of the centred playhead is later in time.
        let ruler = app.descendants(matching: .any)["timeline.ruler"].firstMatch
        let timeline = app.descendants(matching: .any)["editor.timeline"].frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: timeline.midX + 120, dy: ruler.frame.midY))
            .tap()
        expectation(for: NSPredicate(format: "NOT (label BEGINSWITH '00:00.0')"), evaluatedWith: timecode)
        waitForExpectations(timeout: 3)
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
        tapTool("editor.tool.audio")
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
        // New projects open with the format sheet; keep the default.
        closeFormatSheet()
        // Wait until the editor has settled; presenting a cover mid-transition is dropped.
        XCTAssertTrue(app.descendants(matching: .any)["timeline.clip.0"].waitForExistence(timeout: 5))
    }

    /// Scrolls the editor toolbar in small steps until the tool is on screen, then taps it.
    private func tapTool(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        let width = app.frame.width
        // Frame, not isHittable: hittability errors for off-screen elements.
        for _ in 0..<8 where button.frame.minX < 0 || button.frame.maxX > width {
            let y = button.frame.midY / app.frame.height
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            let dx: CGFloat = button.frame.minX < 0 ? 120 : -120
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
        }
        button.tap()
    }

    private func closeFormatSheet() {
        let done = app.buttons["format.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "New project should offer its format")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 3))
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
