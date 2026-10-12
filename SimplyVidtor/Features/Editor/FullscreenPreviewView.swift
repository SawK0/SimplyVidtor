import SwiftUI

/// Plays the edit edge to edge. Controls hide while playing; tap to show them.
struct FullscreenPreviewView: View {
    let session: EditorSession
    let onClose: () -> Void

    @State private var controlsVisible = true
    /// Bumped on every interaction to restart the auto-hide timer.
    @State private var interaction = 0

    private static let hideDelay: Duration = .seconds(3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerView(player: session.player)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if controlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            controlsVisible.toggle()
            interaction += 1
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
        .foregroundStyle(Theme.Palette.textPrimary)
        .task(id: TimerKey(isPlaying: session.isPlaying, interaction: interaction)) {
            guard session.isPlaying, controlsVisible else { return }
            try? await Task.sleep(for: Self.hideDelay)
            if !Task.isCancelled, session.isPlaying { controlsVisible = false }
        }
    }

    private struct TimerKey: Hashable {
        let isPlaying: Bool
        let interaction: Int
    }

    private var controls: some View {
        VStack {
            HStack {
                CircleIconButton(systemImage: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Exit full screen", action: onClose)
                    .accessibilityIdentifier("fullscreen.close")
                Spacer()
            }
            Spacer()
            CircleIconButton(
                systemImage: session.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: session.isPlaying ? "Pause" : "Play",
                isProminent: true
            ) {
                session.togglePlayback()
                interaction += 1
            }
            .scaleEffect(1.4)
            .accessibilityIdentifier("fullscreen.playPause")
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                Text(Timecode.string(session.currentTime))
                ValueSlider(
                    value: timeBinding,
                    range: 0...max(session.duration, 0.1),
                    onEditingChanged: { editing in
                        if editing { session.pause() }
                        interaction += 1
                    }
                )
                .accessibilityLabel("Playhead")
                .accessibilityIdentifier("fullscreen.scrubber")
                Text(Timecode.string(session.duration))
            }
            .font(Theme.Typography.timecode)
        }
        .padding(Theme.Spacing.gutter)
        .background {
            LinearGradient(colors: [Theme.Palette.scrim, .clear, .clear, Theme.Palette.scrim], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var timeBinding: Binding<Double> {
        Binding(get: { session.currentTime }, set: { session.scrub(to: $0) })
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return FullscreenPreviewView(session: session, onClose: {})
        .preferredColorScheme(.dark)
}
