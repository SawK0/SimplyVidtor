import SwiftUI

/// Fit or fill, scale, rotation and opacity for the selected clip. Dragging,
/// pinching and rotating on the preview does the same.
struct TransformPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    var body: some View {
        ToolPanel(title: "Transform", onDone: onDone) {
            if let clip = session.selectedClip {
                controls(for: clip)
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        let transform = clip.transform
        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                SegmentedPicker(selection: binding(clip, \.mode), options: ClipTransform.Mode.allCases) {
                    Text($0 == .fit ? "Fit" : "Fill")
                }
                .accessibilityIdentifier("editor.transform.mode")
                Button("Reset") { session.edit { $0.setTransform(ClipTransform(), ofClip: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(transform.isIdentity)
                    .accessibilityIdentifier("editor.transform.reset")
            }
            row("Scale", value: Text(transform.scale, format: .percent.precision(.fractionLength(0)))) {
                slider(clip, \.scale, range: ClipTransform.scaleRange, origin: 1, scale: .logarithmic)
                    .accessibilityIdentifier("editor.transform.scale")
            }
            row("Rotate", value: Text(verbatim: "\(Int((transform.rotation * 180 / .pi).rounded()))°")) {
                slider(clip, \.rotation, range: -Double.pi...Double.pi, origin: 0)
                    .accessibilityIdentifier("editor.transform.rotation")
            }
            row("Opacity", value: Text(transform.opacity, format: .percent.precision(.fractionLength(0)))) {
                slider(clip, \.opacity, range: 0...1)
                    .accessibilityIdentifier("editor.transform.opacity")
            }
        }
    }

    private func row(_ title: LocalizedStringKey, value: Text, @ViewBuilder slider: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.callout)
                .frame(width: Theme.Size.toolButtonMinWidth * 1.2, alignment: .leading)
            slider()
            value
                .font(Theme.Typography.timecode)
                .frame(minWidth: Theme.Size.toolButtonMinWidth, alignment: .trailing)
        }
    }

    private func binding<Value>(_ clip: Clip, _ keyPath: WritableKeyPath<ClipTransform, Value>) -> Binding<Value> {
        Binding(
            get: { clip.transform[keyPath: keyPath] },
            set: { value in
                var transform = clip.transform
                transform[keyPath: keyPath] = value
                session.edit { $0.setTransform(transform, ofClip: clip.id) }
            }
        )
    }

    private func slider(
        _ clip: Clip, _ keyPath: WritableKeyPath<ClipTransform, Double>, range: ClosedRange<Double>,
        origin: Double? = nil, scale: SliderMath.Scale = .linear
    ) -> some View {
        ValueSlider(
            value: binding(clip, keyPath),
            range: range,
            origin: origin,
            scale: scale,
            onEditingChanged: { editing in
                if editing {
                    session.beginInteractiveEdit()
                } else {
                    Task { await session.endInteractiveEdit() }
                }
            }
        )
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return TransformPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
