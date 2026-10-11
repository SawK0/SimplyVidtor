import XCTest

final class SimplyVidtorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testAppLaunchesToProjects() throws {
        XCTAssertTrue(app.buttons["projects.newProject"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNewProjectFlowReachesEditorAndExport() throws {
        app.buttons["projects.newProject"].tap()

        let add = app.buttons["mediaPicker.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        let export = app.buttons["editor.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 3), "Editor did not open after picking media")
        export.tap()

        let closeExport = app.buttons["export.close"]
        XCTAssertTrue(closeExport.waitForExistence(timeout: 3))
        closeExport.tap()
        XCTAssertTrue(closeExport.waitForNonExistence(timeout: 3))

        app.buttons["editor.close"].tap()
        XCTAssertTrue(app.buttons["projects.newProject"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCancellingPickerStaysOnProjects() throws {
        app.buttons["projects.newProject"].tap()

        let close = app.buttons["mediaPicker.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()

        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["editor.export"].exists)
    }

    @MainActor
    func testEditorAudioToolOpensPickerOnAudioTab() throws {
        app.buttons["projects.newProject"].tap()
        app.buttons["mediaPicker.add"].tap()

        let audioTool = app.buttons["editor.tool.audio"]
        XCTAssertTrue(audioTool.waitForExistence(timeout: 3))
        audioTool.tap()

        XCTAssertTrue(app.staticTexts["Imported audio with preview lands in M1."].waitForExistence(timeout: 3))
    }
}
