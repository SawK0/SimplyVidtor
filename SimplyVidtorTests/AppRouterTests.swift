import Testing
@testable import SimplyVidtor

@MainActor
struct AppRouterTests {
    @Test func newProjectOpensEditorOnlyAfterSheetDismisses() throws {
        let router = AppRouter()
        router.startNewProject()
        #expect(router.sheet == .newProjectPicker)

        let project = try Project(name: "New")
        router.finishNewProject(project)
        #expect(router.sheet == nil)
        #expect(router.openProject == nil)

        router.sheetDidDismiss()
        #expect(router.openProject === project)
    }

    @Test func cancellingThePickerDoesNotOpenTheEditor() {
        let router = AppRouter()
        router.startNewProject()
        router.cancelSheet()
        router.sheetDidDismiss()
        #expect(router.openProject == nil)
    }

    @Test func swipeDismissedPickerDoesNotReopenPreviousProject() throws {
        let router = AppRouter()
        router.startNewProject()
        router.finishNewProject(try Project(name: "First"))
        router.sheetDidDismiss()
        router.closeEditor()

        // A later picker that is swiped away must not resurrect the old project.
        router.startNewProject()
        router.sheet = nil
        router.sheetDidDismiss()
        #expect(router.openProject == nil)
    }

    @Test func openAndCloseExistingProject() throws {
        let router = AppRouter()
        let project = try Project(name: "Existing")
        router.open(project)
        #expect(router.openProject === project)
        router.closeEditor()
        #expect(router.openProject == nil)
    }
}
