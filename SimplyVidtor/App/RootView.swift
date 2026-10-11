import SwiftData
import SwiftUI

struct RootView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var context
    @Environment(\.mediaStore) private var store

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
        .fullScreenCover(item: $router.modal, onDismiss: router.modalDidDismiss) { modal in
            switch modal {
            case .newProjectPicker:
                MediaPickerView(
                    tab: .media,
                    onCancel: router.cancelModal,
                    onAdd: createProject
                )
            }
        }
        .fullScreenCover(item: $router.openProject) { project in
            EditorView(project: project, onClose: router.closeEditor)
        }
        .task { try? library.removeUnusedMedia() }
    }

    private var library: ProjectLibrary { ProjectLibrary(context: context, store: store) }

    private func createProject(with clips: [Clip]) {
        do {
            let project = try library.create(timeline: Timeline(clips: clips))
            router.finishNewProject(project)
            Task { try? await library.updateCover(of: project) }
        } catch {
            router.cancelModal()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
