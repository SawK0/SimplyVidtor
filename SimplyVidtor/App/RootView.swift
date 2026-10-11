import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-componentGallery") {
            ComponentGallery()
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ProjectsView(
            projects: ProjectSummary.samples,
            onNewProject: router.startNewProject,
            onOpen: router.open
        )
        .sheet(item: $router.sheet, onDismiss: router.sheetDidDismiss) { sheet in
            switch sheet {
            case .newProjectPicker:
                MediaPickerSheet(
                    tab: .media,
                    onCancel: router.cancelSheet,
                    onAdd: { router.finishNewProject(.untitled()) }
                )
            }
        }
        .fullScreenCover(item: $router.openProject) { project in
            EditorView(project: project, onClose: router.closeEditor)
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
