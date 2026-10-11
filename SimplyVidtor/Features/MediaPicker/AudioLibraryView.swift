import PhotosUI
import SwiftData
import SwiftUI

struct AudioLibraryView: View {
    @Binding var selection: AudioAsset?
    let player: AudioPreviewPlayer

    @Environment(\.modelContext) private var context
    @Environment(\.mediaStore) private var store
    @Query(sort: \AudioAsset.importedAt, order: .reverse) private var assets: [AudioAsset]

    @State private var isImportingFile = false
    @State private var isPickingVideo = false
    @State private var videoItem: PhotosPickerItem?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var library: AudioLibrary { AudioLibrary(context: context, store: store) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Button { isImportingFile = true } label: {
                    Label("From Files", systemImage: "folder")
                }
                .accessibilityIdentifier("audio.importFiles")
                Button { isPickingVideo = true } label: {
                    Label("From Video", systemImage: "film")
                }
                .accessibilityIdentifier("audio.extractFromVideo")
            }
            .buttonStyle(.secondary)
            .disabled(isWorking)
            .padding(.horizontal, Theme.Spacing.gutter)

            if assets.isEmpty {
                ContentUnavailableView(
                    "No Audio Yet",
                    systemImage: "music.note.list",
                    description: Text("Import a song or voiceover from Files, or use the sound from a video.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(assets) { asset in
                        row(for: asset)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Palette.accent)
            }
        }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $isPickingVideo, selection: $videoItem, matching: .videos, preferredItemEncoding: .current)
        .onChange(of: videoItem) { _, item in
            if let item { extractAudio(from: item) }
        }
        .alert(
            "Couldn’t add audio",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for asset: AudioAsset) -> some View {
        let isPlaying = player.playingID == asset.id
        let isSelected = selection?.id == asset.id
        return HStack(spacing: Theme.Spacing.sm) {
            CircleIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: isPlaying ? "Pause preview" : "Play preview"
            ) {
                player.toggle(asset.id, url: store.url(for: asset.mediaFile))
            }
            .accessibilityIdentifier("audio.play.\(asset.title)")

            Button {
                selection = isSelected ? nil : asset
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(asset.title)
                            .font(Theme.Typography.body)
                            .lineLimit(1)
                        Text(Duration.seconds(asset.duration), format: .time(pattern: .minuteSecond))
                            .font(Theme.Typography.timecode)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(Theme.Typography.title)
                        .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("audio.row.\(asset.title)")
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Theme.Palette.separator)
    }

    private func importFiles(_ urls: [URL]) {
        isWorking = true
        Task {
            var failures = 0
            var lastImported: AudioAsset?
            for url in urls {
                do {
                    lastImported = try await library.importFile(at: url)
                } catch {
                    failures += 1
                }
            }
            isWorking = false
            if urls.count == 1, let lastImported { selection = lastImported }
            if failures > 0 {
                errorMessage = String(localized: "^[\(failures) file](inflect: true) couldn’t be imported.")
            }
        }
    }

    private func extractAudio(from item: PhotosPickerItem) {
        isWorking = true
        Task {
            defer {
                isWorking = false
                videoItem = nil
            }
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                let title = String(localized: "Sound from video")
                selection = try await library.extractAudio(fromMovieAt: movie.url, title: title)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for asset in offsets.map({ assets[$0] }) {
            if selection?.id == asset.id { selection = nil }
            if player.playingID == asset.id { player.stop() }
            try? library.delete(asset)
        }
    }
}

#Preview {
    AudioLibraryView(selection: .constant(nil), player: AudioPreviewPlayer())
        .modelContainer(PreviewData.container())
        .background(Theme.Palette.bgBase)
        .preferredColorScheme(.dark)
}
