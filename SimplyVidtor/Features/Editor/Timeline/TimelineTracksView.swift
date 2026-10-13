import SwiftUI

/// Ruler, clip track and audio track, laid out in timeline points. Leading and
/// trailing padding of half the visible width lets time 0 and the end reach the playhead.
struct TimelineTracksView: View {
    let session: EditorSession
    let metrics: TimelineMetrics
    let inset: CGFloat
    let store: MediaStore
    /// The clip being dragged to a new position, and the finger's x in track coordinates.
    let reordering: (id: Clip.ID, x: CGFloat)?

    /// While trimming a clip's start, clips from that index on are drawn shifted
    /// by this much so the clip's right edge stays put under the finger.
    @State private var leadingTrim: (index: Int, shift: CGFloat)?
    /// The selected text as it was when the current timeline drag began.
    @State private var textDragStart: TextItem?
    /// The selected audio item as it was when the current drag began.
    @State private var audioDragStart: AudioItem?

    private var timeline: Timeline { session.timeline }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RulerView(duration: timeline.duration, metrics: metrics)
                .frame(height: Theme.Size.rulerHeight)
                .contentShape(.rect)
                // The playhead stays centred; tapping a time scrolls it there.
                .onTapGesture(coordinateSpace: .local) { location in
                    Task { await session.seek(to: metrics.time(forOffset: location.x)) }
                }
                .accessibilityIdentifier("timeline.ruler")
            clipTrack
                .frame(height: Theme.Size.timelineClipHeight)
            textTrack
                .frame(height: Theme.Size.textTrackHeight)
            audioTrack
                .frame(height: Theme.Size.audioTrackHeight)
        }
        .padding(.horizontal, inset)
        // minWidth: 0 keeps a long item (e.g. a song) from widening the content,
        // which the hosting view would centre, pushing the other rows off screen.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    session.select(nil)
                    session.selectTransition(after: nil)
                }
        }
    }

    private var clipTrack: some View {
        HStack(spacing: 0) {
            ForEach(Array(timeline.clips.enumerated()), id: \.element.id) { index, clip in
                clipView(clip, at: index)
                    // Clips joined by a transition overlap.
                    .padding(.trailing, -metrics.width(of: timeline.overlap(afterClipAt: index)))
            }
        }
        .overlay(alignment: .leading) {
            if session.selectedClipID == nil, reordering == nil, leadingTrim == nil {
                ForEach(Array(timeline.clips.dropLast().enumerated()), id: \.element.id) { index, clip in
                    transitionButton(after: clip, at: index)
                }
            }
        }
    }

    /// Sits on the cut (or the middle of the overlap) after clip `index`.
    private func transitionButton(after clip: Clip, at index: Int) -> some View {
        let hasTransition = clip.transition != nil
        let isSelected = session.selectedTransitionClipID == clip.id
        let center = timeline.startTime(ofClipAt: index + 1) + timeline.overlap(afterClipAt: index) / 2
        return Button {
            session.selectTransition(after: clip.id)
        } label: {
            Image(systemName: "arrow.left.and.right")
                .font(Theme.Typography.caption.weight(.bold))
                .foregroundStyle(hasTransition || isSelected ? Theme.Palette.onAccent : Theme.Palette.textPrimary)
                .frame(width: Theme.Size.transitionButton, height: Theme.Size.transitionButton)
                .background(hasTransition || isSelected ? Theme.Palette.accent : Theme.Palette.bgSurfaceRaised,
                            in: .rect(cornerRadius: Theme.Radius.clip / 2))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.clip / 2)
                        .strokeBorder(isSelected ? Theme.Palette.textPrimary : .clear, lineWidth: Theme.Size.selectionBorder)
                }
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .offset(x: metrics.offset(for: center) - Theme.Size.minTapTarget / 2)
        .accessibilityLabel(hasTransition ? "Transition \(index + 1), \(clip.transition?.kind.title ?? "")" : "Add transition \(index + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("timeline.transition.\(index)")
    }

    private func clipView(_ clip: Clip, at index: Int) -> some View {
        let isSelected = session.selectedClipID == clip.id
        let isReordering = reordering?.id == clip.id
        let width = metrics.width(of: clip.duration)
        return FilmstripView(clip: clip, width: width, store: store)
            .overlay {
                if isSelected && !isReordering {
                    SelectionFrame(
                        onLeadingDrag: { trim(clip.id, at: index, leading: true, by: $0) },
                        onTrailingDrag: { trim(clip.id, at: index, leading: false, by: $0) },
                        onEnded: finishTrim
                    )
                }
            }
            .offset(x: displayOffset(for: clip, at: index, width: width))
            .scaleEffect(isReordering ? 1.06 : 1)
            .shadow(color: isReordering ? Theme.Palette.shadow : .clear, radius: 8)
            .zIndex(isReordering ? 1 : 0)
            .onTapGesture { session.select(clip.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clip \(index + 1)")
            .accessibilityValue(accessibilityValue(for: clip))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { session.select(clip.id) }
            .accessibilityAction(named: "Move Left") { move(clip.id, to: index - 1) }
            .accessibilityAction(named: "Move Right") { move(clip.id, to: index + 1) }
            .accessibilityIdentifier("timeline.clip.\(index)")
    }

    private func displayOffset(for clip: Clip, at index: Int, width: CGFloat) -> CGFloat {
        if let reordering, reordering.id == clip.id {
            return reordering.x - (metrics.offset(for: timeline.startTime(ofClipAt: index)) + width / 2)
        }
        if let leadingTrim, index >= leadingTrim.index { return leadingTrim.shift }
        return 0
    }

    // MARK: - Trim

    private func trim(_ id: Clip.ID, at index: Int, leading: Bool, by translation: CGFloat) {
        session.beginInteractiveEdit()
        let delta = Double(translation / metrics.pointsPerSecond)
        var baseWidth: CGFloat = 0
        session.updateInteractiveEdit { timeline in
            guard let i = timeline.index(ofClip: id) else { return }
            let clip = timeline.clips[i]
            baseWidth = metrics.width(of: clip.duration)
            if leading {
                timeline.trimStart(ofClip: id, toSource: clip.sourceStart + delta * clip.speed)
            } else {
                timeline.trimEnd(ofClip: id, toSource: clip.sourceEnd + delta * clip.speed)
            }
        }
        if leading, let i = timeline.index(ofClip: id) {
            leadingTrim = (index, baseWidth - metrics.width(of: timeline.clips[i].duration))
        }
    }

    private func finishTrim() {
        leadingTrim = nil
        Task { await session.endInteractiveEdit() }
    }

    // MARK: - Reorder

    private func move(_ id: Clip.ID, to destination: Int) {
        guard destination >= 0, destination < timeline.clips.count else { return }
        Task { await session.update { $0.moveClip(id, to: destination) } }
    }

    private func accessibilityValue(for clip: Clip) -> String {
        let kind = clip.kind == .photo ? String(localized: "Photo") : String(localized: "Video")
        let seconds = clip.duration.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(kind), \(seconds) seconds")
    }

    private func textLabel(_ item: TextItem, index: Int) -> String {
        let name = item.isSticker ? String(localized: "Sticker \(index + 1)") : String(localized: "Text \(index + 1)")
        return item.motion.isEmpty ? name : String(localized: "\(name), animated")
    }

    private var textTrack: some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(timeline.textItems.enumerated()), id: \.element.id) { index, item in
                let isSelected = session.selectedTextID == item.id
                HStack(spacing: Theme.Spacing.xxs) {
                    Label(item.text, systemImage: item.isSticker ? "face.smiling" : "textformat")
                        .labelStyle(.titleAndIcon)
                    if !item.motion.isEmpty {
                        Image(systemName: "sparkles")
                    }
                }
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(width: metrics.width(of: item.duration), alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Palette.trackText, in: .rect(cornerRadius: Theme.Radius.clip))
                    .overlay {
                        if isSelected {
                            SelectionFrame(
                                onLeadingDrag: { dragText(item, by: $0) { $0.trimmingStart(to: $0.timelineStart + $1) } },
                                onTrailingDrag: { dragText(item, by: $0) { $0.trimmingEnd(to: $0.timelineEnd + $1) } },
                                onEnded: endTextDrag
                            )
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                dragText(item, by: drag.translation.width) { $0.moved(toStart: $0.timelineStart + $1) }
                            }
                            .onEnded { _ in endTextDrag() },
                        including: isSelected ? .all : .subviews
                    )
                    .offset(x: metrics.offset(for: item.timelineStart))
                    .onTapGesture { session.selectText(item.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(textLabel(item, index: index))
                    .accessibilityValue(item.text)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { session.selectText(item.id) }
                    .accessibilityIdentifier("timeline.text.\(index)")
            }
        }
    }

    /// Applies `change(start, seconds)` to the text as it was when the drag began.
    private func dragText(_ item: TextItem, by translation: CGFloat, _ change: (TextItem, Double) -> TextItem) {
        let start = textDragStart ?? item
        textDragStart = start
        session.editText(change(start, Double(translation / metrics.pointsPerSecond)), byDrag: true)
    }

    private func endTextDrag() {
        textDragStart = nil
        session.endDrag()
    }

    private var audioTrack: some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(timeline.audioItems.enumerated()), id: \.element.id) { index, item in
                let isSelected = session.selectedAudioID == item.id
                AudioWaveformView(
                    item: item,
                    width: metrics.width(of: item.sourceDuration),
                    store: store
                )
                    .overlay {
                        if isSelected {
                            SelectionFrame(
                                onLeadingDrag: { dragAudio(item, by: $0) { $0.trimmingStart(by: $1) } },
                                onTrailingDrag: { dragAudio(item, by: $0) { $0.trimmingEnd(by: $1) } },
                                onEnded: endAudioDrag
                            )
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                dragAudio(item, by: drag.translation.width) { $0.moved(toStart: $0.timelineStart + $1) }
                            }
                            .onEnded { _ in endAudioDrag() },
                        including: isSelected ? .all : .subviews
                    )
                    .offset(x: metrics.offset(for: item.timelineStart))
                    .onTapGesture { session.selectAudio(isSelected ? nil : item.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Audio \(index + 1)")
                    .accessibilityValue(String(localized: "\(item.sourceDuration.formatted(.number.precision(.fractionLength(1)))) seconds"))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { session.selectAudio(item.id) }
                    .accessibilityIdentifier("timeline.audio.\(index)")
            }
        }
    }

    /// Applies `change(start, seconds)` to the item as it was when the drag began.
    private func dragAudio(_ item: AudioItem, by translation: CGFloat, _ change: @escaping (AudioItem, Double) -> AudioItem) {
        let start = audioDragStart ?? item
        audioDragStart = start
        let delta = Double(translation / metrics.pointsPerSecond)
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { $0.updateAudio(change(start, delta)) }
    }

    private func endAudioDrag() {
        audioDragStart = nil
        Task { await session.endInteractiveEdit() }
    }
}

/// Accent outline with a grab handle on each edge.
private struct SelectionFrame: View {
    let onLeadingDrag: (CGFloat) -> Void
    let onTrailingDrag: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            handle(systemImage: "chevron.compact.left", label: "Trim start", id: "timeline.trim.leading", onDrag: onLeadingDrag)
            Spacer(minLength: 0)
            handle(systemImage: "chevron.compact.right", label: "Trim end", id: "timeline.trim.trailing", onDrag: onTrailingDrag)
        }
        .padding(.trailing, Theme.Size.clipGap)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.clip)
                .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Size.selectionBorder)
                .padding(.trailing, Theme.Size.clipGap)
        }
    }

    private func handle(systemImage: String, label: LocalizedStringKey, id: String, onDrag: @escaping (CGFloat) -> Void) -> some View {
        Image(systemName: systemImage)
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Palette.onAccent)
            .frame(width: Theme.Size.trimHandleWidth)
            .frame(maxHeight: .infinity)
            .background(Theme.Palette.accent, in: .rect(cornerRadius: Theme.Radius.clip))
            .contentShape(.rect.inset(by: -Theme.Spacing.xs))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded { _ in onEnded() }
            )
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier(id)
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
    @State private var reordering: (id: Clip.ID, x: CGFloat)?

    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width / 2
            TimelineScrollView(
                contentWidth: metrics.width(of: contentDuration) + geo.size.width,
                offset: metrics.offset(for: session.currentTime),
                isScrollEnabled: !session.isDragging,
                onScrub: { session.scrub(to: metrics.time(forOffset: $0)) },
                onInteractionChanged: { if $0 { session.pause() } },
                onLongPress: { state, x in reorder(state, trackX: x - inset) }
            ) {
                TimelineTracksView(session: session, metrics: metrics, inset: inset, store: store, reordering: reordering)
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
        .sensoryFeedback(.selection, trigger: session.selectedClipID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.timeline")
    }

    private var contentDuration: Double { session.timeline.duration }

    /// Long-press a clip, then drag: other clips reflow as the finger passes their midpoints.
    private func reorder(_ state: UIGestureRecognizer.State, trackX: CGFloat) {
        let time = metrics.time(forOffset: trackX)
        switch state {
        case .began:
            guard !session.isEditingInteractively,
                  let index = session.timeline.clipIndex(at: time)
            else { return }
            session.beginInteractiveEdit()
            session.selectedClipID = nil
            reordering = (session.timeline.clips[index].id, trackX)
        case .changed:
            guard let id = reordering?.id else { return }
            reordering = (id, trackX)
            session.updateInteractiveEdit { timeline in
                timeline.moveClip(id, to: timeline.reorderDestination(movingClip: id, toTime: time))
            }
        case .ended, .cancelled, .failed:
            guard reordering != nil else { return }
            reordering = nil
            Task { await session.endInteractiveEdit() }
        default:
            break
        }
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
            .accessibilityElement()
            .accessibilityLabel("Playhead")
            .accessibilityValue("\(Timecode.string(session.currentTime)) of \(Timecode.string(session.duration))")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1.0 : -1.0
                session.scrub(to: session.currentTime + step)
            }
    }
}

/// An audio item on the timeline: its waveform, with fades shaded.
private struct AudioWaveformView: View {
    let item: AudioItem
    let width: CGFloat
    let store: MediaStore

    @State private var peaks: [Float] = []

    private static let barSpacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, item.sourceDuration > 0 else { return }
            var bars = Path()
            for x in stride(from: CGFloat(0), to: size.width, by: Self.barSpacing) {
                let time = item.sourceStart + Double(x / size.width) * item.sourceDuration
                let index = min(max(Int(time * Double(Waveform.resolution)), 0), peaks.count - 1)
                let height = max(CGFloat(peaks[index]) * size.height * 0.8, 1)
                bars.addRect(CGRect(x: x, y: (size.height - height) / 2, width: Self.barSpacing - 1, height: height))
            }
            context.fill(bars, with: .color(Theme.Palette.onAccent.opacity(0.45)))

            // Fades darken toward silence.
            let perSecond = size.width / item.sourceDuration
            var fades = Path()
            if item.fadeIn > 0 {
                fades.move(to: .zero)
                fades.addLine(to: CGPoint(x: item.fadeIn * perSecond, y: 0))
                fades.addLine(to: CGPoint(x: 0, y: size.height))
            }
            if item.fadeOut > 0 {
                fades.move(to: CGPoint(x: size.width, y: 0))
                fades.addLine(to: CGPoint(x: size.width - item.fadeOut * perSecond, y: 0))
                fades.addLine(to: CGPoint(x: size.width, y: size.height))
            }
            context.fill(fades, with: .color(Theme.Palette.scrim))
        }
        .overlay(alignment: .leading) {
            Image(systemName: "music.note")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.onAccent)
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(Theme.Palette.trackAudio)
        .clipShape(.rect(cornerRadius: Theme.Radius.clip))
        .task(id: item.mediaFile) {
            peaks = await Waveform.shared.peaks(of: store.url(for: item.mediaFile))
        }
    }
}
