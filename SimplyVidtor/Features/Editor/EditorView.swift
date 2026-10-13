import SwiftData
import SwiftUI

struct EditorView: View {
    let project: Project
    /// New projects open with the format sheet so the frame can be chosen first.
    var showsFormatOnOpen = false
    let onClose: () -> Void

    @State private var pickerTab: MediaPickerTab?
    /// The picker's clips go on an overlay track instead of the main track.
    @State private var picksOverlay = false
    @State private var explainsVideoLoad = false
    @State private var activeTool: Tool?
    @State private var isExporting = false
    @State private var isFullscreen = false
    @State private var isEditingFormat = false
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
            MediaPickerView(tab: tab, onCancel: {
                pickerTab = nil
                picksOverlay = false
            }, onAdd: append)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            if let session {
                FullscreenPreviewView(session: session) { isFullscreen = false }
            }
        }
        .sheet(isPresented: $isEditingFormat) {
            if let session {
                ProjectFormatSheet(session: session) { isEditingFormat = false }
            }
        }
        .sheet(isPresented: $isExporting) {
            if let session {
                ExportSheet(session: session, store: store) { isExporting = false }
            }
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
            if id == nil, activeTool?.isClipTool == true { activeTool = nil }
        }
        .onChange(of: session?.selectedAudioID) { _, id in
            if id != nil {
                activeTool = .audio
            } else if activeTool == .audio {
                activeTool = nil
            }
        }
        .onChange(of: session?.selectedTextID) { _, id in
            if let item = session?.selectedText {
                activeTool = item.isSticker ? .sticker : .text
            } else if id != nil {
                activeTool = .text
            } else if activeTool == .text || activeTool == .sticker || activeTool == .motion {
                activeTool = nil
            }
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
        case speed, volume, filters, adjust, crop, transform, transition, text, sticker, audio, motion

        /// Panels that act on the selected clip.
        var isClipTool: Bool { ![.transition, .text, .sticker, .audio, .motion].contains(self) }
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
        case .transform: TransformPanel(session: session, onDone: close)
        case .transition: TransitionPanel(session: session) { session.selectTransition(after: nil) }
        case .text:
            if let id = session.selectedTextID {
                TextPanel(session: session, id: id, onAnimate: { activeTool = .motion }) { session.selectText(nil) }
                    .id(id)
            }
        case .audio: AudioPanel(session: session) { session.selectAudio(nil) }
        case .sticker:
            StickerPanel(session: session, onAnimate: { activeTool = .motion }) {
                session.selectText(nil)
                activeTool = nil
            }
        case .motion:
            MotionPanel(session: session) {
                guard let item = session.selectedText else { return activeTool = nil }
                activeTool = item.isSticker ? .sticker : .text
            }
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
            if showsFormatOnOpen { isEditingFormat = true }
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
            CircleIconButton(systemImage: "aspectratio", accessibilityLabel: "Project format") {
                session?.pause()
                isEditingFormat = true
            }
            .disabled(session == nil)
            .accessibilityIdentifier("editor.format")
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
            // Lighter than the frame's black, so the output frame's edges show.
            Theme.Palette.bgSurface
            if let session {
                PlayerView(player: session.player)
                    .accessibilityHidden(true)
                TextOverlayLayer(session: session)
            } else if loadFailed {
                ContentUnavailableView("Couldn’t Open Project", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let peak = session?.timeline.peakVideoCount, peak.count > Timeline.comfortableVideoCount {
                videoLoadWarning(peak)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session != nil {
                CircleIconButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "Full screen") {
                    isFullscreen = true
                }
                .padding(Theme.Spacing.xs)
                .accessibilityIdentifier("editor.fullscreen")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { playbackBar }
    }

    /// Too many videos at one instant for the phone to decode smoothly.
    private func videoLoadWarning(_ peak: (count: Int, time: Double)) -> some View {
        Button { explainsVideoLoad = true } label: {
            Label(String(localized: "\(peak.count) videos at once"), systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.accent)
                .padding(.horizontal, Theme.Spacing.xs)
                .frame(minHeight: Theme.Size.minTapTarget)
                .background(Theme.Palette.scrim, in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(Theme.Spacing.xs)
        .accessibilityIdentifier("editor.videoLoadWarning")
        .alert("Many Videos at Once", isPresented: $explainsVideoLoad) {
            Button("Show Me") { Task { await session?.seek(to: peak.time) } }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(peak.count) videos play together at \(Timecode.string(peak.time)). Phones decode only a few videos at the same moment, so playback may stutter there. Try a photo, or shorten an overlay.")
        }
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
        if picksOverlay {
            picksOverlay = false
            Task { await session.addOverlays(result.clips) }
            return
        }
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
        // Grows with the tracks, up to a limit; past it the timeline scrolls vertically.
        .frame(height: TimelineLayout.visibleHeight(for: session?.timeline ?? Timeline()))
        .animation(.snappy(duration: 0.25), value: session?.timeline.tracks.count)
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
                ToolButton(title: "Text", systemImage: "textformat") { session?.selectText(UUID()) }
                    .disabled(session == nil)
                    .accessibilityIdentifier("editor.tool.text")
                ToolButton(title: "Stickers", systemImage: "face.smiling") {
                    session?.selectText(nil)
                    activeTool = .sticker
                }
                .disabled(session == nil)
                .accessibilityIdentifier("editor.tool.sticker")
                ToolButton(title: "Audio", systemImage: "music.note") { pickerTab = .audio }
                    .accessibilityIdentifier("editor.tool.audio")
                ToolButton(title: "Overlay", systemImage: "rectangle.on.rectangle") {
                    picksOverlay = true
                    pickerTab = .media
                }
                .disabled(session == nil)
                .accessibilityIdentifier("editor.tool.overlay")
                ToolButton(title: "Magnet", systemImage: "arrow.right.and.line.vertical.and.arrow.left",
                           isSelected: session?.timeline.isMagnetic ?? true) {
                    guard let session else { return }
                    let on = !session.timeline.isMagnetic
                    Task { await session.update { $0.setMagnetic(on) } }
                }
                .disabled(session == nil)
                .accessibilityLabel(session?.timeline.isMagnetic ?? true ? "Magnet on" : "Magnet off")
                .accessibilityIdentifier("editor.tool.magnet")
                ToolMenu(title: "Track", systemImage: "plus.rectangle.on.rectangle") {
                    Button("Video Track", systemImage: "rectangle.on.rectangle") { Task { await session?.addTrack(.video) } }
                    Button("Text Track", systemImage: "textformat") { Task { await session?.addTrack(.text) } }
                    Button("Audio Track", systemImage: "music.note") { Task { await session?.addTrack(.audio) } }
                }
                .disabled(session == nil)
                .accessibilityIdentifier("editor.tool.track")
                ToolButton(title: "Crop", systemImage: "crop") { open(.crop) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.crop")
                ToolButton(title: "Transform", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { open(.transform) }
                    .disabled(session?.timeline.clips.isEmpty ?? true)
                    .accessibilityIdentifier("editor.tool.transform")
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
