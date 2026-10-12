import SwiftUI

/// Brightness, contrast, saturation and warmth for the selected clip.
struct AdjustPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    @State private var parameter: ClipAdjustments.Parameter = .brightness

    var body: some View {
        ToolPanel(title: "Adjust", onDone: onDone) {
            if let clip = session.selectedClip {
                controls(for: clip)
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                ForEach(ClipAdjustments.Parameter.allCases, id: \.self) { item in
                    ToolButton(title: Self.title(of: item), systemImage: Self.symbol(of: item), isSelected: item == parameter) {
                        parameter = item
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if clip.adjustments[item] != 0 {
                            Circle()
                                .fill(Theme.Palette.accent)
                                .frame(width: Theme.Spacing.xxs * 1.5, height: Theme.Spacing.xxs * 1.5)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("editor.adjust.\(item.rawValue)")
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                ValueSlider(
                    value: binding(for: clip),
                    range: ClipAdjustments.range,
                    step: 0.01,
                    origin: 0,
                    onEditingChanged: { editing in
                        if editing {
                            session.beginInteractiveEdit()
                        } else {
                            Task { await session.endInteractiveEdit() }
                        }
                    }
                )
                .accessibilityLabel(Self.title(of: parameter))
                .accessibilityIdentifier("editor.adjust.slider")
                Text(Self.label(for: clip.adjustments[parameter]))
                    .font(Theme.Typography.timecode)
                    .frame(minWidth: Theme.Size.toolButtonMinWidth / 1.5, alignment: .trailing)
                    .accessibilityIdentifier("editor.adjust.value")
                Button("Reset") { session.edit { $0.resetAdjustments(ofClip: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(clip.adjustments.isIdentity)
                    .accessibilityIdentifier("editor.adjust.reset")
            }
        }
    }

    private func binding(for clip: Clip) -> Binding<Double> {
        let parameter = parameter
        return Binding(
            get: { clip.adjustments[parameter] },
            set: { value in session.edit { $0.setAdjustment(parameter, to: value, ofClip: clip.id) } }
        )
    }

    /// -100...100, like most photo editors.
    static func label(for value: Double) -> String {
        let amount = Int((value * 100).rounded())
        return amount > 0 ? "+\(amount)" : "\(amount)"
    }

    static func title(of parameter: ClipAdjustments.Parameter) -> LocalizedStringKey {
        switch parameter {
        case .brightness: "Brightness"
        case .contrast: "Contrast"
        case .saturation: "Saturation"
        case .warmth: "Warmth"
        }
    }

    static func symbol(of parameter: ClipAdjustments.Parameter) -> String {
        switch parameter {
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .saturation: "drop"
        case .warmth: "thermometer.medium"
        }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return AdjustPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
