import SwiftData
import SwiftUI

struct EditorView: View {
    let project: Project
    let onClose: () -> Void

    @State private var pickerTab: MediaPickerTab?
    @State private var isExporting = false
    @State private var session: EditorSession?
    @State private var loadFailed = false
    @Environment(\.modelContext) private var context
    @Environment(\.mediaStore) private var store

    var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            timeline
            toolbar
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .fullScreenCover(item: $pickerTab) { tab in
            MediaPickerView(tab: tab, onCancel: { pickerTab = nil }, onAdd: append)
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(onClose: { isExporting = false })
        }
        .task { await openSession() }
        .onDisappear { session?.pause() }
    }

    private func openSession() async {
        guard session == nil else { return }
        do {
            let session = try EditorSession(project: project, store: store)
            await session.rebuild()
            self.session = session
        } catch {
            loadFailed = true
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close project", action: onClose)
                .accessibilityIdentifier("editor.close")
            Text(project.name)
                .font(Theme.Typography.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button("Export") {
                session?.pause()
                isExporting = true
            }
                .buttonStyle(.primaryCompact)
                .accessibilityIdentifier("editor.export")
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let session {
                PlayerView(player: session.player)
                    .accessibilityHidden(true)
            } else if loadFailed {
                ContentUnavailableView("Couldn’t Open Project", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { session?.togglePlayback() }
        .safeAreaInset(edge: .bottom, spacing: 0) { playbackBar }
    }

    private var playbackBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            let isPlaying = session?.isPlaying ?? false
            CircleIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: isPlaying ? "Pause" : "Play"
            ) {
                session?.togglePlayback()
            }
            .accessibilityIdentifier("editor.playPause")
            .disabled(session == nil)

            Text("\(Timecode.string(session?.currentTime ?? 0)) / \(Timecode.string(session?.duration ?? 0))")
                .font(Theme.Typography.timecode)
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityIdentifier("editor.timecode")
            Spacer()
            CircleIconButton(systemImage: "plus", accessibilityLabel: "Add clip", isProminent: true) {
                pickerTab = .media
            }
            .accessibilityIdentifier("editor.addClip")
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Palette.bgBase)
    }

    private func append(_ result: MediaPickerResult) {
        pickerTab = nil
        guard let session else { return }
        let hadClips = !session.timeline.clips.isEmpty
        Task {
            await session.update { timeline in
                timeline.insert(result.clips, at: timeline.clips.count)
                if let audio = result.audio { timeline.audioItems.append(audio) }
            }
            if !hadClips {
                try? await ProjectLibrary(context: context, store: store).updateCover(of: project)
            }
        }
    }

    private var timeline: some View {
        Group {
            if let session {
                EditorTimelineView(session: session, store: store)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Size.rulerHeight + Theme.Size.timelineClipHeight + Theme.Size.audioTrackHeight + 2 * Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ToolButton(title: "Split", systemImage: "scissors") {}
                ToolButton(title: "Speed", systemImage: "gauge.with.dots.needle.50percent") {}
                ToolButton(title: "Volume", systemImage: "speaker.wave.2") {}
                ToolButton(title: "Filters", systemImage: "camera.filters") {}
                ToolButton(title: "Adjust", systemImage: "slider.horizontal.3") {}
                ToolButton(title: "Text", systemImage: "textformat") {}
                ToolButton(title: "Audio", systemImage: "music.note") { pickerTab = .audio }
                    .accessibilityIdentifier("editor.tool.audio")
                ToolButton(title: "Crop", systemImage: "crop") {}
                ToolButton(title: "Duplicate", systemImage: "plus.square.on.square") {}
                ToolButton(title: "Delete", systemImage: "trash") {}
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .background(Theme.Palette.bgSurface)
    }
}

#Preview {
    EditorView(project: PreviewData.sampleProjects()[0], onClose: {})
        .modelContainer(PreviewData.container(withSamples: false))
        .preferredColorScheme(.dark)
}
