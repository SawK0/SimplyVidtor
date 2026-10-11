import Observation

/// App-level navigation. The editor presents its own picker and export.
@Observable
final class AppRouter {
    enum Modal: String, Identifiable {
        case newProjectPicker
        var id: Self { self }
    }

    var modal: Modal?
    var openProject: Project?

    /// Opened after the picker dismisses; SwiftUI drops a cover presented mid-dismiss.
    private var pendingProject: Project?

    func startNewProject() {
        modal = .newProjectPicker
    }

    func finishNewProject(_ project: Project) {
        pendingProject = project
        modal = nil
    }

    func cancelModal() {
        pendingProject = nil
        modal = nil
    }

    /// Call from the picker's `onDismiss`.
    func modalDidDismiss() {
        if let project = pendingProject {
            pendingProject = nil
            openProject = project
        }
    }

    func open(_ project: Project) {
        openProject = project
    }

    func closeEditor() {
        openProject = nil
    }
}
