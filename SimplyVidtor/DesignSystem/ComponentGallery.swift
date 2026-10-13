import SwiftUI

struct ComponentGallery: View {
    private enum Resolution: String, CaseIterable { case p720 = "720p", p1080 = "1080p", k4 = "4K" }

    @State private var resolution = Resolution.p1080
    @State private var smartHDR = true
    @State private var speed = 1.0
    @State private var brightness = 0.0
    @State private var selectedTool = "Speed"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                section("Colors") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
                        swatch("bg/base", Theme.Palette.bgBase)
                        swatch("surface", Theme.Palette.bgSurface)
                        swatch("raised", Theme.Palette.bgSurfaceRaised)
                        swatch("separator", Theme.Palette.separator)
                        swatch("text", Theme.Palette.textPrimary)
                        swatch("text/2", Theme.Palette.textSecondary)
                        swatch("accent", Theme.Palette.accent)
                        swatch("audio", Theme.Palette.trackAudio)
                        swatch("text trk", Theme.Palette.trackText)
                        swatch("danger", Theme.Palette.danger)
                    }
                }

                section("Typography") {
                    Text("Display").font(Theme.Typography.display)
                    Text("Title").font(Theme.Typography.title)
                    Text("Headline").font(Theme.Typography.headline)
                    Text("Body").font(Theme.Typography.body)
                    Text("Callout").font(Theme.Typography.callout).foregroundStyle(Theme.Palette.textSecondary)
                    Text("Caption").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                    Text("00:12.4 / 01:05.0").font(Theme.Typography.timecode)
                }

                section("Buttons") {
                    Button("Export") {}.buttonStyle(.primary)
                    Button("Add 3 clips") {}.buttonStyle(.primary).disabled(true)
                    Button("Cancel") {}.buttonStyle(.secondary)
                    Button("Delete Project") {}.buttonStyle(.destructive)
                    Button("Export") {}.buttonStyle(.primaryCompact)
                    HStack(spacing: Theme.Spacing.sm) {
                        CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {}
                        CircleIconButton(systemImage: "arrow.uturn.backward", accessibilityLabel: "Undo") {}
                        CircleIconButton(systemImage: "arrow.uturn.forward", accessibilityLabel: "Redo") {}
                            .disabled(true)
                        CircleIconButton(systemImage: "plus", accessibilityLabel: "Add clip", isProminent: true) {}
                    }
                }

                section("Tool buttons") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(Self.tools, id: \.0) { title, icon in
                                ToolButton(title: LocalizedStringKey(title), systemImage: icon, isSelected: selectedTool == title) {
                                    selectedTool = title
                                }
                            }
                            ToolMenu(title: "Track", systemImage: "plus.rectangle.on.rectangle") {
                                Button("Video") {}
                                Button("Text") {}
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                    .background(Theme.Palette.bgSurface, in: .rect(cornerRadius: Theme.Radius.card))
                }

                section("Tool panel") {
                    ToolPanel(title: "Speed", onDone: {}) {
                        Toggle("Keep pitch", isOn: $smartHDR).toggleStyle(.accentSwitch)
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.card))
                }

                section("Controls") {
                    SegmentedPicker(selection: $resolution, options: Resolution.allCases) { Text($0.rawValue) }
                    Toggle("Smart HDR", isOn: $smartHDR).toggleStyle(.accentSwitch)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Speed \(speed, format: .number.precision(.fractionLength(1)))×")
                            .font(Theme.Typography.callout)
                        ValueSlider(value: $speed, range: 0.1...10, step: 0.1, origin: 1, scale: .logarithmic)
                            .accessibilityLabel("Speed")
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Brightness \(brightness, format: .number.precision(.fractionLength(2)))")
                            .font(Theme.Typography.callout)
                        ValueSlider(value: $brightness, range: -1...1, origin: 0)
                            .accessibilityLabel("Brightness")
                    }
                }
            }
            .padding(Theme.Spacing.gutter)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
    }

    private static let tools = [
        ("Split", "scissors"),
        ("Speed", "gauge.with.dots.needle.50percent"),
        ("Volume", "speaker.wave.2"),
        ("Filters", "camera.filters"),
        ("Adjust", "slider.horizontal.3"),
        ("Text", "textformat"),
        ("Audio", "music.note"),
        ("Crop", "crop"),
        ("Duplicate", "plus.square.on.square"),
        ("Delete", "trash"),
    ]

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xxs) {
            RoundedRectangle(cornerRadius: Theme.Radius.clip)
                .fill(color)
                .frame(height: Theme.Size.circleButton)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.clip)
                        .strokeBorder(Theme.Palette.separator, lineWidth: Theme.Size.hairline)
                }
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
    }
}

#Preview {
    ComponentGallery()
        .preferredColorScheme(.dark)
}
