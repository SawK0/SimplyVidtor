import PhotosUI
import SwiftData
import SwiftUI

enum MediaPickerTab: String, CaseIterable, Identifiable {
    case media, audio
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .media: "Videos & Photos"
        case .audio: "Audio"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all, videos, photos
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .videos: "Videos"
        case .photos: "Photos"
        }
    }

    var pickerFilter: PHPickerFilter {
        switch self {
        case .all: .any(of: [.videos, .images])
        case .videos: .videos
        case .photos: .images
        }
    }
}

struct MediaPickerResult {
    var clips: [Clip]
    var audio: AudioItem?
}

/// Presented as a full-screen cover: inside a sheet the inline photo picker
/// strips the sheet's safe area and the header ends up under the status bar.
struct MediaPickerView: View {
    @State var tab: MediaPickerTab
    let onCancel: () -> Void
    let onAdd: (MediaPickerResult) -> Void

    @Environment(\.mediaStore) private var store
    @State private var filter = MediaFilter.all
    @State private var selection: [PhotosPickerItem] = []
    @State private var selectedAudio: AudioAsset?
    @State private var player = AudioPreviewPlayer()
    @State private var importTask: Task<Void, Never>?
    @State private var pendingClips: [Clip]?

    var body: some View {
        ZStack {
            photosPicker
                .opacity(tab == .media ? 1 : 0)
                .allowsHitTesting(tab == .media)
            audioTab
                .opacity(tab == .audio ? 1 : 0)
                .allowsHitTesting(tab == .audio)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { addButton }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .overlay { if importTask != nil { importingOverlay } }
        .alert(
            "Some items couldn’t be added",
            isPresented: Binding(get: { pendingClips != nil }, set: { if !$0 { finishWithPendingClips() } })
        ) {
            Button("OK") {}
        } message: {
            Text("They may be unavailable offline or in an unsupported format.")
        }
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("Add Media")
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: close)
                    .accessibilityIdentifier("mediaPicker.close")
            }
            SegmentedPicker(selection: $tab, options: MediaPickerTab.allCases) { Text($0.title) }
            if tab == .media {
                SegmentedPicker(selection: $filter, options: MediaFilter.allCases) { Text($0.title) }
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.bgBase)
    }

    private var addButton: some View {
        Button(action: startImport) {
            switch (selection.count, selectedAudio != nil) {
            case (0, false): Text("Add")
            case (0, true): Text("Add audio")
            case (let count, false): Text("Add ^[\(count) clip](inflect: true)")
            case (let count, true): Text("Add ^[\(count) clip](inflect: true) & audio")
            }
        }
        .buttonStyle(.primary)
        .disabled(!canAdd)
        .accessibilityIdentifier("mediaPicker.add")
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Palette.bgBase)
    }

    private var photosPicker: some View {
        PhotosPicker(
            selection: $selection,
            // Continuous: the inline picker reports each tap, since its own Add button is hidden.
            selectionBehavior: .continuousAndOrdered,
            matching: filter.pickerFilter,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            Text("Choose Media")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
    }

    private var audioTab: some View {
        AudioLibraryView(selection: $selectedAudio, player: player)
    }

    private var importingOverlay: some View {
        ZStack {
            Theme.Palette.scrim.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Palette.accent)
                Text("Importing…")
                    .font(Theme.Typography.callout)
            }
            .padding(Theme.Spacing.xl)
            .background(Theme.Palette.bgSurfaceRaised, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    private var canAdd: Bool {
        #if DEBUG
        if Self.usesStubMedia { return true }
        #endif
        return !selection.isEmpty || selectedAudio != nil
    }

    private func startImport() {
        player.stop()
        #if DEBUG
        if Self.usesStubMedia {
            finish(with: [.video(mediaFile: "stub.mov", duration: 5)])
            return
        }
        #endif
        guard !selection.isEmpty else {
            finish(with: [])
            return
        }
        let items = selection
        importTask = Task {
            let result = await MediaImporter(store: store).importItems(items)
            guard !Task.isCancelled else { return }
            importTask = nil
            if result.failedCount == 0 {
                finish(with: result.clips)
            } else {
                pendingClips = result.clips
            }
        }
    }

    private func finishWithPendingClips() {
        guard let clips = pendingClips else { return }
        pendingClips = nil
        if clips.isEmpty && selectedAudio == nil { return }
        finish(with: clips)
    }

    private func finish(with clips: [Clip]) {
        onAdd(MediaPickerResult(clips: clips, audio: selectedAudio?.makeItem()))
    }

    /// Cancelling mid-import leaves copied files behind; `removeUnusedMedia` cleans them up.
    private func close() {
        player.stop()
        importTask?.cancel()
        importTask = nil
        onCancel()
    }

    #if DEBUG
    /// UI tests can't drive the out-of-process photo picker, so `-stubMediaPicker`
    /// makes Add return a placeholder clip without a selection.
    private static let usesStubMedia = ProcessInfo.processInfo.arguments.contains("-stubMediaPicker")
    #endif
}

#Preview {
    MediaPickerView(tab: .audio, onCancel: {}, onAdd: { _ in })
        .modelContainer(PreviewData.container())
        .preferredColorScheme(.dark)
}
