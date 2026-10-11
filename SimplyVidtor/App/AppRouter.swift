import Observation

/// App-level navigation. Editor sheets live in the editor.
@Observable
final class AppRouter {
    enum Sheet: String, Identifiable {
        case newProjectPicker
        var id: Self { self }
    }

    var sheet: Sheet?
    var openProject: ProjectSummary?

    /// Opened after the sheet dismisses; SwiftUI drops a cover presented mid-dismiss.
    private var pendingProject: ProjectSummary?

    func startNewProject() {
        sheet = .newProjectPicker
    }

    func finishNewProject(_ project: ProjectSummary) {
        pendingProject = project
        sheet = nil
    }

    func cancelSheet() {
        pendingProject = nil
        sheet = nil
    }

    /// Call from the sheet's `onDismiss`.
    func sheetDidDismiss() {
        if let project = pendingProject {
            pendingProject = nil
            openProject = project
        }
    }

    func open(_ project: ProjectSummary) {
        openProject = project
    }

    func closeEditor() {
        openProject = nil
    }
}
