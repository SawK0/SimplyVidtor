import SwiftUI

/// Ruler, clip track and audio track, laid out in timeline points. Leading and
/// trailing padding of half the visible width lets time 0 and the end reach the playhead.
struct TimelineTracksView: View {
    let timeline: Timeline
    let metrics: TimelineMetrics
    let inset: CGFloat
    let store: MediaStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RulerView(duration: timeline.duration, metrics: metrics)
                .frame(height: Theme.Size.rulerHeight)
            HStack(spacing: 0) {
                ForEach(Array(timeline.clips.enumerated()), id: \.element.id) { index, clip in
                    FilmstripView(clip: clip, width: metrics.width(of: clip.duration), store: store)
                        .accessibilityIdentifier("timeline.clip.\(index)")
                }
            }
            .frame(height: Theme.Size.timelineClipHeight)
            audioTrack
                .frame(height: Theme.Size.audioTrackHeight)
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var audioTrack: some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(timeline.audioItems) { item in
                Label("Audio", systemImage: "music.note")
                    .labelStyle(.iconOnly)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(width: metrics.width(of: item.sourceDuration), alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Palette.trackAudio, in: .rect(cornerRadius: Theme.Radius.clip))
                    .offset(x: metrics.offset(for: item.timelineStart))
            }
        }
    }
}

private struct RulerView: View {
    let duration: Double
    let metrics: TimelineMetrics

    var body: some View {
        let interval = metrics.tickInterval
        let count = Int(duration / interval) + 1
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(0..<max(count, 1), id: \.self) { index in
                let seconds = Double(index) * interval
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Rectangle()
                        .fill(Theme.Palette.separator)
                        .frame(width: Theme.Size.hairline, height: Theme.Spacing.xs)
                    Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize()
                }
                .offset(x: metrics.offset(for: seconds))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A clip drawn as a strip of frames sampled across its source range.
private struct FilmstripView: View {
    let clip: Clip
    let width: CGFloat
    let store: MediaStore

    @Environment(\.displayScale) private var displayScale
    @State private var frames: [CGImage?] = []

    private var frameWidth: CGFloat { Theme.Size.timelineClipHeight * 0.75 }
    private var frameCount: Int { max(1, Int((width / frameWidth).rounded(.up))) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<frameCount, id: \.self) { index in
                Group {
                    if index < frames.count, let frame = frames[index] {
                        Image(decorative: frame, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.Palette.bgSurfaceRaised
                    }
                }
                .frame(width: frameWidth)
                .clipped()
            }
        }
        .frame(width: max(width - Theme.Size.clipGap, 1), alignment: .leading)
        .clipShape(.rect(cornerRadius: Theme.Radius.clip))
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .leading) {
            if clip.kind == .photo {
                Image(systemName: "photo")
                    .font(Theme.Typography.caption)
                    .padding(Theme.Spacing.xxs)
                    .background(Theme.Palette.scrim, in: .rect(cornerRadius: Theme.Spacing.xxs))
                    .padding(Theme.Spacing.xxs)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task(id: FrameRequest(clip: clip, count: frameCount)) {
            let step = clip.sourceDuration / Double(frameCount)
            let times = (0..<frameCount).map { clip.sourceStart + (Double($0) + 0.5) * step }
            let size = Int(Theme.Size.timelineClipHeight * displayScale)
            frames = await ThumbnailCache.shared.frames(of: clip, atSourceTimes: times, maxPixelSize: size, store: store)
        }
    }

    private struct FrameRequest: Equatable {
        let clip: Clip
        let count: Int
    }
}

/// The timeline with its fixed centre playhead and pinch-to-zoom.
struct EditorTimelineView: View {
    let session: EditorSession
    let store: MediaStore

    @State private var metrics = TimelineMetrics()
    @State private var zoomBase: TimelineMetrics?

    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width / 2
            TimelineScrollView(
                contentWidth: metrics.width(of: session.duration) + geo.size.width,
                offset: metrics.offset(for: session.currentTime),
                onScrub: { session.scrub(to: metrics.time(forOffset: $0)) },
                onInteractionChanged: { if $0 { session.pause() } }
            ) {
                TimelineTracksView(timeline: session.timeline, metrics: metrics, inset: inset, store: store)
            }
            .overlay { playhead }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let base = zoomBase ?? metrics
                    zoomBase = base
                    metrics = base.zoomed(by: value.magnification)
                }
                .onEnded { _ in zoomBase = nil }
        )
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(Timecode.string(session.currentTime)) of \(Timecode.string(session.duration))")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 : -1.0
            session.scrub(to: session.currentTime + step)
        }
        .accessibilityIdentifier("editor.timeline")
    }

    private var playhead: some View {
        Rectangle()
            .fill(Theme.Palette.accent)
            .frame(width: Theme.Size.playheadWidth)
            .overlay(alignment: .top) {
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: Theme.Spacing.xs, height: Theme.Spacing.xs)
            }
            .allowsHitTesting(false)
    }
}
