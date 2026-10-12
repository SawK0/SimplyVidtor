import SwiftUI

/// Volume and mute for the selected clip.
struct VolumePanel: View {
    let session: EditorSession
    let onDone: () -> Void

    var body: some View {
        ToolPanel(title: "Volume", onDone: onDone) {
            if let clip = session.selectedClip {
                if clip.kind == .photo {
                    Text("Photos have no sound.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTapTarget)
                } else {
                    controls(for: clip)
                }
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: Self.symbol(for: clip))
                    .font(.system(size: Theme.Size.toolIcon))
                    .frame(width: Theme.Size.toolIcon * 1.5)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .accessibilityHidden(true)
                ValueSlider(
                    value: volumeBinding(for: clip),
                    range: Clip.volumeRange,
                    step: 0.01,
                    onEditingChanged: { editing in
                        if editing {
                            session.beginInteractiveEdit()
                        } else {
                            Task { await session.endInteractiveEdit() }
                        }
                    }
                )
                .accessibilityLabel("Volume")
                .accessibilityIdentifier("editor.volume.slider")
                .disabled(clip.isMuted)
                .opacity(clip.isMuted ? 0.4 : 1)
                Text(clip.volume, format: .percent.precision(.fractionLength(0)))
                    .font(Theme.Typography.timecode)
                    .frame(minWidth: Theme.Size.toolButtonMinWidth, alignment: .trailing)
                    .accessibilityIdentifier("editor.volume.value")
            }
            Toggle("Mute", isOn: muteBinding(for: clip))
                .toggleStyle(.accentSwitch)
                .accessibilityIdentifier("editor.volume.mute")
        }
    }

    private func volumeBinding(for clip: Clip) -> Binding<Double> {
        Binding(
            get: { clip.volume },
            set: { volume in session.edit { $0.setVolume(volume, ofClip: clip.id) } }
        )
    }

    private func muteBinding(for clip: Clip) -> Binding<Bool> {
        Binding(
            get: { clip.isMuted },
            set: { muted in session.edit { $0.setMuted(muted, ofClip: clip.id) } }
        )
    }

    static func symbol(for clip: Clip) -> String {
        switch clip.effectiveVolume {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return VolumePanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
