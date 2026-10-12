import SwiftUI

/// Speed for the selected clip on a log slider (1× in the middle), plus keep pitch.
struct SpeedPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    var body: some View {
        ToolPanel(title: "Speed", onDone: onDone) {
            if let clip = session.selectedClip {
                controls(for: clip)
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.label(for: clip.speed))
                    .font(Theme.Typography.title.monospacedDigit())
                    .accessibilityIdentifier("editor.speed.value")
                Spacer()
                Text(Timecode.string(clip.duration))
                    .font(Theme.Typography.timecode)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .accessibilityLabel("Clip length \(Timecode.string(clip.duration))")
                Button("Reset") { session.edit { $0.setSpeed(1, ofClip: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(clip.speed == 1)
                    .accessibilityIdentifier("editor.speed.reset")
            }

            ValueSlider(
                value: speedBinding(for: clip),
                range: Clip.speedRange,
                step: 0.1,
                origin: 1,
                scale: .logarithmic,
                onEditingChanged: { editing in
                    if editing {
                        session.beginInteractiveEdit()
                    } else {
                        Task { await session.endInteractiveEdit() }
                    }
                }
            )
            .accessibilityLabel("Speed")
            .accessibilityIdentifier("editor.speed.slider")

            HStack {
                ForEach([Clip.speedRange.lowerBound, 1, Clip.speedRange.upperBound], id: \.self) { mark in
                    Text(Self.label(for: mark))
                        .frame(maxWidth: .infinity, alignment: mark == 1 ? .center : mark < 1 ? .leading : .trailing)
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .accessibilityHidden(true)

            if clip.kind == .video {
                Toggle("Keep pitch", isOn: pitchBinding(for: clip))
                    .toggleStyle(.accentSwitch)
                    .accessibilityIdentifier("editor.speed.keepPitch")
            }
        }
    }

    private func speedBinding(for clip: Clip) -> Binding<Double> {
        Binding(
            get: { clip.speed },
            set: { speed in
                let rounded = (speed * 100).rounded() / 100
                session.edit { $0.setSpeed(rounded, ofClip: clip.id) }
            }
        )
    }

    private func pitchBinding(for clip: Clip) -> Binding<Bool> {
        Binding(
            get: { clip.preservesPitch },
            set: { keep in session.edit { $0.setPreservesPitch(keep, ofClip: clip.id) } }
        )
    }

    static func label(for speed: Double) -> String {
        "\(speed.formatted(.number.precision(.fractionLength(1))))×"
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return SpeedPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
