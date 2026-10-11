import SwiftUI

struct EditorView: View {
    let project: ProjectSummary
    let onClose: () -> Void

    private enum Sheet: Identifiable {
        case picker(MediaPickerTab)
        case export

        var id: String {
            switch self {
            case .picker(let tab): "picker-\(tab.rawValue)"
            case .export: "export"
            }
        }
    }

    @State private var sheet: Sheet?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            timeline
            toolbar
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .picker(let tab):
                MediaPickerSheet(tab: tab, onCancel: { self.sheet = nil }, onAdd: { self.sheet = nil })
            case .export:
                ExportSheet(onClose: { self.sheet = nil })
            }
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
            Button("Export") { sheet = .export }
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
            Text("00:00.0 / \(Duration.seconds(project.duration), format: .time(pattern: .minuteSecond))")
                .font(Theme.Typography.timecode)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(Theme.Spacing.sm)
        }
        .frame(maxHeight: .infinity)
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
                sheet = .picker(.media)
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
                ToolButton(title: "Audio", systemImage: "music.note") { sheet = .picker(.audio) }
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
    EditorView(project: ProjectSummary.samples[0], onClose: {})
        .preferredColorScheme(.dark)
}
