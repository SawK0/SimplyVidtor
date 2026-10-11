import SwiftData
import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context

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
            onNewProject: router.startNewProject,
            onOpen: router.open
        )
        .sheet(item: $router.sheet, onDismiss: router.sheetDidDismiss) { sheet in
            switch sheet {
            case .newProjectPicker:
                MediaPickerSheet(
                    tab: .media,
                    onCancel: router.cancelSheet,
                    onAdd: createProject
                )
            }
        }
        .fullScreenCover(item: $router.openProject) { project in
            EditorView(project: project, onClose: router.closeEditor)
        }
    }

    private func createProject() {
        do {
            router.finishNewProject(try ProjectLibrary(context: context).create())
        } catch {
            router.cancelSheet()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
