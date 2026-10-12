import SwiftUI

/// Volume, fades and delete for the selected audio item.
struct AudioPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    /// Longest fade the sliders offer.
    private static let fadeLimit: Double = 5

    var body: some View {
        ToolPanel(title: "Audio", onDone: onDone) {
            if let item = session.selectedAudio {
                controls(for: item)
            }
        }
    }

    private func controls(for item: AudioItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            row("Volume", value: Text(item.volume, format: .percent.precision(.fractionLength(0)))) {
                slider(for: item, \.volume, range: AudioItem.volumeRange, step: 0.01)
                    .accessibilityLabel("Volume")
                    .accessibilityIdentifier("editor.audio.volume")
            }
            let fadeRange = 0...max(min(Self.fadeLimit, item.maximumFade), 0.1)
            row("Fade In", value: seconds(item.fadeIn)) {
                slider(for: item, \.fadeIn, range: fadeRange, step: 0.1)
                    .accessibilityLabel("Fade in")
                    .accessibilityIdentifier("editor.audio.fadeIn")
            }
            row("Fade Out", value: seconds(item.fadeOut)) {
                slider(for: item, \.fadeOut, range: fadeRange, step: 0.1)
                    .accessibilityLabel("Fade out")
                    .accessibilityIdentifier("editor.audio.fadeOut")
            }
            Button("Delete Audio", role: .destructive) {
                session.edit { $0.removeAudio(item.id) }
            }
            .font(Theme.Typography.callout.weight(.semibold))
            .foregroundStyle(Theme.Palette.danger)
            .frame(minHeight: Theme.Size.minTapTarget)
            .accessibilityIdentifier("editor.audio.delete")
        }
    }

    private func row(_ title: LocalizedStringKey, value: Text, @ViewBuilder slider: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.callout)
                .frame(width: Theme.Size.toolButtonMinWidth * 1.4, alignment: .leading)
            slider()
            value
                .font(Theme.Typography.timecode)
                .frame(minWidth: Theme.Size.toolButtonMinWidth, alignment: .trailing)
        }
    }

    private func seconds(_ value: Double) -> Text {
        Text("\(value.formatted(.number.precision(.fractionLength(1)))) s")
    }

    private func slider(
        for item: AudioItem, _ keyPath: WritableKeyPath<AudioItem, Double>, range: ClosedRange<Double>, step: Double
    ) -> some View {
        ValueSlider(
            value: Binding(
                get: { item[keyPath: keyPath] },
                set: { value in
                    var changed = item
                    changed[keyPath: keyPath] = value
                    session.edit { $0.updateAudio(changed) }
                }
            ),
            range: range,
            step: step,
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
    return AudioPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
