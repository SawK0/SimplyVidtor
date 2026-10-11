import XCTest

final class SimplyVidtorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
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
        XCTAssertTrue(app.staticTexts["Imported audio with preview lands in M1."].waitForExistence(timeout: 3))
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
    }

    private func openMenu(on projectName: String) {
        let card = app.buttons["projects.card.\(projectName)"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.press(forDuration: 1)
    }
}
