import SwiftUI

/// Fit or fill, scale, rotation and opacity for the selected clip. Dragging,
/// pinching and rotating on the preview does the same. Once the clip has
/// keyframes, changes set the keyframe at the playhead.
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

    /// Source time at the playhead, clamped to the clip.
    private func sourceTime(for clip: Clip) -> Double {
        session.selectedClipSourceTime ?? clip.sourceStart
    }

    private func controls(for clip: Clip) -> some View {
        let transform = clip.transform(atSource: sourceTime(for: clip))
        return VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                SegmentedPicker(selection: binding(clip, \.mode), options: ClipTransform.Mode.allCases) {
                    Text($0 == .fit ? "Fit" : "Fill")
                }
                .accessibilityIdentifier("editor.transform.mode")
                keyframes(for: clip)
                Button("Reset") { session.edit { $0.resetTransform(ofClip: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(transform.isIdentity && clip.transformKeyframes.isEmpty)
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

    private func keyframes(for clip: Clip) -> some View {
        let source = session.selectedClipSourceTime
        let track = clip.transformKeyframes
        let onKeyframe = source.flatMap { track.index(near: $0, tolerance: KeyframeControls.tolerance * clip.speed) }
        return KeyframeControls(
            times: track.times.compactMap { session.timelineTime(ofClip: clip.id, atSource: $0) },
            playhead: session.currentTime,
            isEnabled: source != nil,
            easing: onKeyframe.map { track.keyframes[$0].easing },
            onToggle: {
                guard let source else { return }
                session.edit { $0.toggleTransformKeyframe(ofClip: clip.id, atSource: source) }
            },
            onJump: { time in Task { await session.seek(to: time) } },
            onEasing: { easing in
                guard let source else { return }
                session.edit { $0.setTransformEasing(easing, ofClip: clip.id, atSource: source) }
            }
        )
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
        let source = sourceTime(for: clip)
        let atPlayhead = session.selectedClipSourceTime
        return Binding(
            get: { clip.transform(atSource: source)[keyPath: keyPath] },
            set: { value in
                var transform = clip.transform(atSource: source)
                transform[keyPath: keyPath] = value
                session.edit { $0.setTransform(transform, ofClip: clip.id, atSource: atPlayhead) }
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
