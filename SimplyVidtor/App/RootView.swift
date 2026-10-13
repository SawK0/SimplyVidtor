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
            EditorView(project: project, showsFormatOnOpen: router.openedProjectIsNew, onClose: router.closeEditor)
        }
        .task {
            try? library.removeUnusedMedia()
            #if DEBUG
            await seedSampleAudioIfRequested()
            #endif
        }
    }

    private var library: ProjectLibrary { ProjectLibrary(context: context, store: store) }

    private func createProject(with result: MediaPickerResult) {
        do {
            let timeline = Timeline(clips: result.clips, audioItems: result.audio.map { [$0] } ?? [])
            let project = try library.create(timeline: timeline)
            router.finishNewProject(project)
            Task { try? await library.updateCover(of: project) }
        } catch {
            router.cancelModal()
        }
    }

    #if DEBUG
    /// `-seedSampleAudio` adds a 2 s "Sample Tone" and a 60 s "Long Tone" to an
    /// empty audio library, for UI tests.
    private func seedSampleAudioIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleAudio"),
              (try? context.fetchCount(FetchDescriptor<AudioAsset>())) == 0
        else { return }
        for (name, seconds) in [("Sample Tone", 2.0), ("Long Tone", 60.0)] {
            let url = URL.temporaryDirectory.appending(path: "\(name).wav")
            try? FileManager.default.removeItem(at: url)
            guard (try? ToneGenerator.writeTone(to: url, seconds: seconds)) != nil else { continue }
            _ = try? await AudioLibrary(context: context, store: store).importFile(at: url)
        }
    }
    #endif
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
