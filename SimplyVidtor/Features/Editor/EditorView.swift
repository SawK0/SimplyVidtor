import SwiftData
import SwiftUI

struct EditorView: View {
    let project: Project
    let onClose: () -> Void

    @State private var pickerTab: MediaPickerTab?
    @State private var isExporting = false
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
    }

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close project", action: onClose)
                .accessibilityIdentifier("editor.close")
            Text(project.name)
                .font(Theme.Typography.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button("Export") { isExporting = true }
                .buttonStyle(.primaryCompact)
                .accessibilityIdentifier("editor.export")
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var preview: some View {
        ZStack {
            Theme.Palette.bgSurface
            Image(systemName: "play.fill")
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityLabel("Play")
            Text("00:00.0 / \(Duration.seconds(duration), format: .time(pattern: .minuteSecond))")
                .font(Theme.Typography.timecode)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(Theme.Spacing.sm)
        }
        .frame(maxHeight: .infinity)
    }

    private func append(_ result: MediaPickerResult) {
        pickerTab = nil
        guard var timeline = try? project.loadTimeline() else { return }
        let hadClips = !timeline.clips.isEmpty
        timeline.insert(result.clips, at: timeline.clips.count)
        if let audio = result.audio { timeline.audioItems.append(audio) }
        try? project.save(timeline)
        if !hadClips {
            Task { try? await ProjectLibrary(context: context, store: store).updateCover(of: project) }
        }
    }

    private var duration: Double {
        (try? project.loadTimeline().duration) ?? 0
    }

    private var timeline: some View {
        HStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Radius.clip)
                        .fill(Theme.Palette.bgSurfaceRaised)
                }
            }
            .overlay {
                Rectangle()
                    .fill(Theme.Palette.accent)
                    .frame(width: Theme.Size.playheadWidth)
            }
            .accessibilityElement()
            .accessibilityLabel("Timeline")

            CircleIconButton(systemImage: "plus", accessibilityLabel: "Add clip", isProminent: true) {
                pickerTab = .media
            }
            .accessibilityIdentifier("editor.addClip")
        }
        .frame(height: Theme.Size.timelineClipHeight)
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.md)
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
