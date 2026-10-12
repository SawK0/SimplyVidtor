import SwiftData
import SwiftUI

struct EditorView: View {
    let project: Project
    let onClose: () -> Void

    @State private var pickerTab: MediaPickerTab?
    @State private var activeTool: Tool?
    @State private var isExporting = false
    @State private var session: EditorSession?
    @State private var loadFailed = false
    @Environment(\.modelContext) private var context
    @Environment(\.mediaStore) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            timeline
            if let session, let activeTool {
                panel(for: activeTool, session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                toolbar
            }
        }
        .animation(.snappy(duration: 0.25), value: activeTool)
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .fullScreenCover(item: $pickerTab) { tab in
            MediaPickerView(tab: tab, onCancel: { pickerTab = nil }, onAdd: append)
        }
        .sheet(isPresented: $isExporting) {
            ExportSheet(onClose: { isExporting = false })
        }
        .task { await openSession() }
        .onDisappear {
            session?.pause()
            try? context.save()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { try? context.save() }
        }
        .onChange(of: session?.selectedClipID) { _, id in
            if id == nil, activeTool != .transition { activeTool = nil }
        }
        .onChange(of: session?.selectedTransitionClipID) { _, id in
            if id != nil {
                activeTool = .transition
            } else if activeTool == .transition {
                activeTool = nil
            }
        }
    }

    /// Panels that replace the toolbar while open.
    private enum Tool {
        case speed, volume, filters, adjust, crop, transition
    }

    @ViewBuilder
    private func panel(for tool: Tool, session: EditorSession) -> some View {
        let close = { activeTool = nil }
        switch tool {
        case .speed: SpeedPanel(session: session, onDone: close)
        case .volume: VolumePanel(session: session, onDone: close)
        case .filters: FiltersPanel(session: session, store: store, onDone: close)
        case .adjust: AdjustPanel(session: session, onDone: close)
        case .crop: CropPanel(session: session, store: store, onDone: close)
        case .transition: TransitionPanel(session: session) { session.selectTransition(after: nil) }
        }
    }

    private func open(_ tool: Tool) {
        guard session?.selectClipAtPlayheadIfNeeded() == true else { return }
        activeTool = tool
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
            CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo") {
                Task { await session?.undo() }
            }
            .disabled(!(session?.canUndo ?? false))
            .accessibilityIdentifier("editor.undo")
            CircleIconButton(systemImage: "arrow.uturn.forward", accessibilityLabel: "Redo") {
                Task { await session?.redo() }
            }
            .disabled(!(session?.canRedo ?? false))
            .accessibilityIdentifier("editor.redo")
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
            await session.insertAtPlayhead(result.clips, audio: result.audio)
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
                ToolButton(title: "Split", systemImage: "scissors") {
                    Task { await session?.splitAtPlayhead() }
                }
                .disabled(!(session?.canSplit ?? false))
                .accessibilityIdentifier("editor.tool.split")
                ToolButton(title: "Speed", systemImage: "gauge.with.dots.needle.50percent") { open(.speed) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.speed")
                ToolButton(title: "Volume", systemImage: "speaker.wave.2") { open(.volume) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.volume")
                ToolButton(title: "Filters", systemImage: "camera.filters") { open(.filters) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.filters")
                ToolButton(title: "Adjust", systemImage: "slider.horizontal.3") { open(.adjust) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.adjust")
                ToolButton(title: "Text", systemImage: "textformat") {}
                ToolButton(title: "Audio", systemImage: "music.note") { pickerTab = .audio }
                    .accessibilityIdentifier("editor.tool.audio")
                ToolButton(title: "Crop", systemImage: "crop") { open(.crop) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.crop")
                ToolButton(title: "Duplicate", systemImage: "plus.square.on.square") {
                    Task { await session?.duplicateSelected() }
                }
                .disabled(session?.selectedClipID == nil)
                .accessibilityIdentifier("editor.tool.duplicate")
                ToolButton(title: "Delete", systemImage: "trash") {
                    Task { await session?.deleteSelected() }
                }
                .disabled(session?.selectedClipID == nil)
                .accessibilityIdentifier("editor.tool.delete")
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
