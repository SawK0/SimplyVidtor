import SwiftUI

/// Transition at the selected cut: kind, length and apply to all.
struct TransitionPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    var body: some View {
        ToolPanel(title: "Transition", onDone: onDone) {
            if let clip = session.transitionClip {
                controls(for: clip)
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            SegmentedPicker(selection: kindBinding(for: clip), options: [nil] + TransitionKind.allCases.map(Optional.some)) {
                Text($0?.title ?? String(localized: "None"))
            }
            .accessibilityIdentifier("editor.transition.kind")

            HStack(spacing: Theme.Spacing.sm) {
                ValueSlider(
                    value: durationBinding(for: clip),
                    range: ClipTransition.durationRange,
                    step: 0.1,
                    onEditingChanged: { editing in
                        if editing {
                            session.beginInteractiveEdit()
                        } else {
                            Task { await session.endInteractiveEdit() }
                        }
                    }
                )
                .accessibilityLabel("Duration")
                .accessibilityIdentifier("editor.transition.duration")
                Text("\((clip.transition?.duration ?? ClipTransition.defaultDuration).formatted(.number.precision(.fractionLength(1)))) s")
                    .font(Theme.Typography.timecode)
                    .frame(minWidth: Theme.Size.toolButtonMinWidth / 1.5, alignment: .trailing)
                Button("Apply to All") { session.edit { $0.applyTransitionToAll(from: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(session.timeline.clips.dropLast().allSatisfy { $0.transition == clip.transition })
                    .accessibilityIdentifier("editor.transition.applyAll")
            }
            .disabled(clip.transition == nil)
            .opacity(clip.transition == nil ? 0.4 : 1)
        }
    }

    private func kindBinding(for clip: Clip) -> Binding<TransitionKind?> {
        Binding(
            get: { clip.transition?.kind },
            set: { kind in
                let duration = clip.transition?.duration ?? ClipTransition.defaultDuration
                session.edit { $0.setTransition(kind.map { ClipTransition(kind: $0, duration: duration) }, afterClip: clip.id) }
            }
        )
    }

    private func durationBinding(for clip: Clip) -> Binding<Double> {
        Binding(
            get: { clip.transition?.duration ?? ClipTransition.defaultDuration },
            set: { duration in
                guard let kind = clip.transition?.kind else { return }
                session.edit { $0.setTransition(ClipTransition(kind: kind, duration: duration), afterClip: clip.id) }
            }
        )
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectTransition(after: session.timeline.clips.first?.id)
    return TransitionPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
