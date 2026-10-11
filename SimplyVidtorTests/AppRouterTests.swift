import Testing
@testable import SimplyVidtor

@MainActor
struct AppRouterTests {
    @Test func newProjectOpensEditorOnlyAfterPickerDismisses() throws {
        let router = AppRouter()
        router.startNewProject()
        #expect(router.modal == .newProjectPicker)

        let project = try Project(name: "New")
        router.finishNewProject(project)
        #expect(router.modal == nil)
        #expect(router.openProject == nil)

        router.modalDidDismiss()
        #expect(router.openProject === project)
    }

    @Test func cancellingThePickerDoesNotOpenTheEditor() {
        let router = AppRouter()
        router.startNewProject()
        router.cancelModal()
        router.modalDidDismiss()
        #expect(router.openProject == nil)
    }

    @Test func swipeDismissedPickerDoesNotReopenPreviousProject() throws {
        let router = AppRouter()
        router.startNewProject()
        router.finishNewProject(try Project(name: "First"))
        router.modalDidDismiss()
        router.closeEditor()

        // A later picker that is swiped away must not resurrect the old project.
        router.startNewProject()
        router.modal = nil
        router.modalDidDismiss()
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
