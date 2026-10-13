import SwiftUI

/// The project's frame shape, resolution and frame rate. Each change is an
/// undoable edit; the preview shows the new frame right away.
struct ProjectFormatSheet: View {
    let session: EditorSession
    let onDone: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 3)

    private var format: ProjectFormat { session.timeline.format }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Format")
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.primaryCompact)
                    .accessibilityIdentifier("format.done")
            }

            section("Shape") {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                    ForEach([nil] + AspectRatio.allCases.map(Optional.some), id: \.self) { ratio in
                        shapeTile(ratio)
                    }
                }
            }
            section("Resolution") {
                SegmentedPicker(selection: binding(\.resolution), options: ProjectFormat.resolutions) {
                    Text(ProjectFormat.title(ofResolution: $0))
                }
                .accessibilityIdentifier("format.resolution")
            }
            section("Frame Rate") {
                SegmentedPicker(selection: binding(\.frameRate), options: ProjectFormat.frameRates) { Text("\($0) fps") }
                    .accessibilityIdentifier("format.frameRate")
            }

            let size = outputSize
            Text(verbatim: "\(Int(size.width)) × \(Int(size.height)) · \(format.frameRate) fps")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityIdentifier("format.summary")
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.gutter)
        .foregroundStyle(Theme.Palette.textPrimary)
        .presentationDetents([.fraction(0.7), .large])
        .presentationBackground(Theme.Palette.bgSurface)
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// Full-resolution output size; the preview itself is capped.
    private var outputSize: CGSize {
        ExportSettings(resolution: ExportSettings.Resolution(rawValue: format.resolution) ?? .p1080)
            .renderSize(for: session.renderSize)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
        }
    }

    private func shapeTile(_ ratio: AspectRatio?) -> some View {
        let isSelected = format.aspectRatio == ratio
        return Button {
            session.edit { $0.format.aspectRatio = ratio }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Group {
                    if let ratio {
                        RoundedRectangle(cornerRadius: Theme.Radius.clip / 2)
                            .strokeBorder(lineWidth: Theme.Size.selectionBorder)
                            .aspectRatio(ratio.value, contentMode: .fit)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: Theme.Size.toolIcon))
                    }
                }
                .frame(height: Theme.Size.toolIcon * 1.6)
                Text(ratio?.title ?? String(localized: "Match Clip"))
                    .font(Theme.Typography.caption)
            }
            .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight * 1.4)
            .background(isSelected ? Theme.Palette.accent : Theme.Palette.bgSurfaceRaised, in: .rect(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(ratio?.title ?? String(localized: "Match first clip"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("format.shape.\(ratio?.rawValue ?? "match")")
    }

    private func binding(_ keyPath: WritableKeyPath<ProjectFormat, Int>) -> Binding<Int> {
        Binding(
            get: { format[keyPath: keyPath] },
            set: { value in session.edit { $0.format[keyPath: keyPath] = value } }
        )
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return Color.clear.sheet(isPresented: .constant(true)) {
        ProjectFormatSheet(session: session, onDone: {})
    }
    .preferredColorScheme(.dark)
}
