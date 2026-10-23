import SwiftUI

/// Ruler, clip track and audio track, laid out in timeline points. Leading and
/// trailing padding of half the visible width lets time 0 and the end reach the playhead.
struct TimelineTracksView: View {
    let session: EditorSession
    let metrics: TimelineMetrics
    let inset: CGFloat
    let store: MediaStore
    /// The clip being dragged to a new position, and the finger in track coordinates.
    let reordering: (id: Clip.ID, x: CGFloat, y: CGFloat)?
    /// The row a main-track clip would drop onto.
    var dropTarget: TimelineLayout.Row?
    /// Opens the picker to add clips to a video track.
    var onAddMedia: (Track.ID) -> Void = { _ in }

    /// Drags read finger positions here, to find the row under them.
    static let coordinateSpace = "timelineTracks"

    /// While trimming a clip's start, clips from that index on are drawn shifted
    /// by this much so the clip's right edge stays put under the finger.
    @State private var leadingTrim: (index: Int, shift: CGFloat)?
    /// The selected text as it was when the current timeline drag began.
    @State private var textDragStart: TextItem?
    /// The selected audio item as it was when the current drag began.
    @State private var audioDragStart: AudioItem?
    /// An overlay being dragged up onto the main track.
    @State private var overlayDropsOnMain = false

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
                .background(dropHighlight(dropTarget == .main || overlayDropsOnMain))
                .zIndex(1)
            // Each row draws over the rows above it.
            ForEach(TimelineLayout.displayTracks(of: timeline)) { track in
                row(for: track)
                    .frame(height: TimelineLayout.height(of: track.kind))
                    .background(dropHighlight(dropTarget == .track(track)))
            }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .padding(.horizontal, inset)
        // minWidth: 0 keeps a long item (e.g. a song) from widening the content,
        // which the hosting view would centre, pushing the other rows off screen.
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: deselect)
        }
    }

    private var clipTrack: some View {
        HStack(spacing: 0) {
            ForEach(Array(timeline.clips.enumerated()), id: \.element.id) { index, clip in
                clipView(clip, at: index)
                    // Gaps (magnet off) push clips right; clips joined by a transition overlap.
                    .padding(.leading, metrics.width(of: timeline.gap(beforeClipAt: index)))
                    .padding(.trailing, -metrics.width(of: timeline.overlap(afterClipAt: index)))
            }
        }
        .overlay(alignment: .leading) {
            if session.selectedClipID == nil, reordering == nil, leadingTrim == nil {
                ForEach(Array(timeline.clips.dropLast().enumerated()), id: \.element.id) { index, clip in
                    // Only clips that touch can have a transition.
                    if timeline.gap(beforeClipAt: index + 1) == 0 {
                        transitionButton(after: clip, at: index)
                    }
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
            // Above the selection frame, so a keyframe at the clip's edge shows.
            .overlay(alignment: .bottom) {
                if !clip.transformKeyframes.isEmpty {
                    KeyframeMarks(offsets: clip.transformKeyframes.times
                        .filter { $0 >= clip.sourceStart - 0.001 && $0 <= clip.sourceEnd + 0.001 }
                        .map { metrics.width(of: ($0 - clip.sourceStart) / clip.speed) })
                        .frame(height: Theme.Size.keyframeMark * 2)
                }
            }
            .offset(x: displayOffset(for: clip, at: index, width: width),
                    y: isReordering ? (reordering?.y ?? 0) - Self.mainRowCenter : 0)
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

    private static let mainRowCenter = Theme.Size.rulerHeight + Theme.Spacing.xs + Theme.Size.timelineClipHeight / 2

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
        // With the magnet off the clip's end stays put by itself.
        if leading, timeline.isMagnetic, let i = timeline.index(ofClip: id) {
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
        let value = String(localized: "\(kind), \(seconds) seconds")
        let keyframes = clip.transformKeyframes.keyframes.count
        return keyframes == 0 ? value : String(localized: "\(value), \(keyframes) keyframes")
    }

    private func textLabel(_ item: TextItem, index: Int) -> String {
        let name = item.isSticker ? String(localized: "Sticker \(index + 1)") : String(localized: "Text \(index + 1)")
        var label = item.motion.isEmpty ? name : String(localized: "\(name), animated")
        if !item.keyframes.isEmpty { label += String(localized: ", \(item.keyframes.keyframes.count) keyframes") }
        return label
    }

    @ViewBuilder
    private func row(for track: Track) -> some View {
        let sameKind = timeline.tracks.filter { $0.kind == track.kind }
        let position = sameKind.firstIndex(of: track) ?? 0
        Group {
            switch track.kind {
            case .video: overlayTrack(track)
            case .text: textTrack(track)
            case .audio: audioTrack(track)
            }
        }
        // Long press an empty part of a row for the track's actions.
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: deselect)
                .contextMenu { trackMenu(track) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.track.\(track.kind.rawValue).\(position)")
    }

    private func dropHighlight(_ isTarget: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.clip)
            .fill(isTarget ? Theme.Palette.accent.opacity(0.2) : .clear)
    }

    @ViewBuilder
    private func trackMenu(_ track: Track) -> some View {
        if track.kind == .video {
            Button("Add Media Here", systemImage: "plus") { onAddMedia(track.id) }
        }
        if track.kind != .audio {
            let visual = timeline.visualTracks
            Button("Bring Forward", systemImage: "square.2.layers.3d.top.filled") {
                Task { await session.update { $0.moveTrack(track.id, up: true) } }
            }
            .disabled(visual.last == track)
            Button("Send Backward", systemImage: "square.2.layers.3d.bottom.filled") {
                Task { await session.update { $0.moveTrack(track.id, up: false) } }
            }
            .disabled(visual.first == track)
        }
        Button("Delete Track", systemImage: "trash", role: .destructive) {
            Task { await session.update { $0.removeTrack(track.id) } }
        }
        .disabled(!timeline.canRemoveTrack(track.id))
    }

    private func deselect() {
        session.select(nil)
        session.selectTransition(after: nil)
    }

    /// The same-kind track `rows` rows away from `trackID` (by a vertical drag of `dy` points).
    private func track(_ trackID: Track.ID, movedBy dy: CGFloat) -> Track.ID {
        guard let kind = timeline.track(trackID)?.kind else { return trackID }
        let sameKind = timeline.tracks.filter { $0.kind == kind }
        guard let index = sameKind.firstIndex(where: { $0.id == trackID }) else { return trackID }
        let pitch = TimelineLayout.height(of: kind) + Theme.Spacing.xs
        let target = min(max(index + Int((dy / pitch).rounded()), 0), sameKind.count - 1)
        return sameKind[target].id
    }

    // MARK: - Overlay clips

    private func overlayTrack(_ track: Track) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(timeline.overlays.enumerated()).filter { $0.element.trackID == track.id }, id: \.element.id) { index, overlay in
                overlayView(overlay, at: index)
            }
        }
    }

    private func overlayView(_ overlay: OverlayClip, at index: Int) -> some View {
        let clip = overlay.clip
        let isSelected = session.selectedClipID == clip.id
        return FilmstripView(clip: clip, width: metrics.width(of: clip.duration), store: store)
            .overlay {
                if isSelected {
                    SelectionFrame(
                        onLeadingDrag: { trimOverlay(clip.id, leading: true, by: $0) },
                        onTrailingDrag: { trimOverlay(clip.id, leading: false, by: $0) },
                        onEnded: { Task { await session.endInteractiveEdit() } }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if !clip.transformKeyframes.isEmpty {
                    KeyframeMarks(offsets: clip.transformKeyframes.times
                        .filter { $0 >= clip.sourceStart - 0.001 && $0 <= clip.sourceEnd + 0.001 }
                        .map { metrics.width(of: ($0 - clip.sourceStart) / clip.speed) })
                        .frame(height: Theme.Size.keyframeMark * 2)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
                    .onChanged { drag in moveOverlay(clip.id, by: drag.translation.width, fingerY: drag.location.y) }
                    .onEnded { drag in
                        // A flick can end before the last change arrives.
                        moveOverlay(clip.id, by: drag.translation.width, fingerY: drag.location.y)
                        finishOverlayMove(clip.id, by: drag.translation.width)
                    },
                including: isSelected ? .all : .subviews
            )
            .offset(x: metrics.offset(for: overlay.timelineStart))
            .onTapGesture { session.select(clip.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Overlay \(index + 1)")
            .accessibilityValue(accessibilityValue(for: clip))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { session.select(clip.id) }
            .accessibilityIdentifier("timeline.overlay.\(index)")
    }

    /// Moves the overlay in time and onto the video track under the finger.
    /// Over the main track it only marks the drop; it moves there when the finger lifts.
    /// Re-applied to the drag's starting timeline, so it reads the overlay's start from there.
    private func moveOverlay(_ id: Clip.ID, by translation: CGFloat, fingerY: CGFloat) {
        let delta = Double(translation / metrics.pointsPerSecond)
        let row = TimelineLayout.row(atY: fingerY, in: timeline)
        overlayDropsOnMain = row == .main
        var target: Track.ID?
        if case .track(let track) = row, track.kind == .video { target = track.id }
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { timeline in
            guard let index = timeline.overlayIndex(of: id) else { return }
            timeline.moveOverlay(id, toStart: timeline.overlays[index].timelineStart + delta, track: target)
        }
    }

    private func finishOverlayMove(_ id: Clip.ID, by translation: CGFloat) {
        if overlayDropsOnMain {
            let delta = Double(translation / metrics.pointsPerSecond)
            session.updateInteractiveEdit { timeline in
                guard let index = timeline.overlayIndex(of: id) else { return }
                timeline.moveToMain(id, at: timeline.overlays[index].timelineStart + delta)
            }
            overlayDropsOnMain = false
        }
        Task { await session.endInteractiveEdit() }
    }

    private func trimOverlay(_ id: Clip.ID, leading: Bool, by translation: CGFloat) {
        let delta = Double(translation / metrics.pointsPerSecond)
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { timeline in
            guard let clip = timeline[clip: id] else { return }
            if leading {
                timeline.trimStart(ofClip: id, toSource: clip.sourceStart + delta * clip.speed)
            } else {
                timeline.trimEnd(ofClip: id, toSource: clip.sourceEnd + delta * clip.speed)
            }
        }
    }

    // MARK: - Text

    private func textTrack(_ track: Track) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(timeline.textItems.enumerated()).filter { $0.element.trackID == track.id }, id: \.element.id) { index, item in
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
                    .overlay(alignment: .bottom) {
                        if !item.keyframes.isEmpty {
                            KeyframeMarks(offsets: item.keyframes.times
                                .filter { $0 >= -0.001 && $0 <= item.duration + 0.001 }
                                .map { metrics.width(of: $0) })
                                .frame(height: Theme.Size.keyframeMark)
                        }
                    }
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
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
                            .onChanged { drag in moveText(item, by: drag.translation) }
                            .onEnded { drag in
                                moveText(item, by: drag.translation)
                                endTextDrag()
                            },
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

    /// Moves the text in time and onto the text track under the finger.
    private func moveText(_ item: TextItem, by translation: CGSize) {
        // `start` is the item as the drag began.
        dragText(item, by: translation.width) { start, delta in
            var moved = start.moved(toStart: start.timelineStart + delta)
            moved.trackID = self.track(start.trackID, movedBy: translation.height)
            return moved
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

    private func audioTrack(_ track: Track) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(timeline.audioItems.enumerated()).filter { $0.element.trackID == track.id }, id: \.element.id) { index, item in
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
                        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
                            .onChanged { drag in moveAudio(item, by: drag.translation) }
                            .onEnded { drag in
                                moveAudio(item, by: drag.translation)
                                endAudioDrag()
                            },
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

    private func moveAudio(_ item: AudioItem, by translation: CGSize) {
        dragAudio(item, by: translation.width) { start, delta in
            var moved = start.moved(toStart: start.timelineStart + delta)
            moved.trackID = self.track(start.trackID, movedBy: translation.height)
            return moved
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
                // Measured in the tracks' space: the handle itself moves as the item is trimmed.
                DragGesture(minimumDistance: 0, coordinateSpace: .named(TimelineTracksView.coordinateSpace))
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded {
                        onDrag($0.translation.width)
                        onEnded()
                    }
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
    @State private var reordering: (id: Clip.ID, x: CGFloat, y: CGFloat)?
    /// Where a long-pressed main-track clip would land: another video track, or nil.
    @State private var dropTrack: Track?
    var onAddMedia: (Track.ID) -> Void = { _ in }
    /// Magnet off: the clip being slid in time, and where the finger started.
    @State private var sliding: (id: Clip.ID, startTime: Double)?

    var body: some View {
        GeometryReader { geo in
            let inset = geo.size.width / 2
            TimelineScrollView(
                contentWidth: metrics.width(of: contentDuration) + geo.size.width,
                contentHeight: TimelineLayout.contentHeight(for: session.timeline),
                offset: metrics.offset(for: session.currentTime),
                isScrollEnabled: !session.isDragging,
                onScrub: { session.scrub(to: metrics.time(forOffset: $0)) },
                onInteractionChanged: { if $0 { session.pause() } },
                onLongPress: { state, point in reorder(state, trackX: point.x - inset, y: point.y) },
                canScroll: { point in
                    !TimelineLayout.grabsSelection(at: CGPoint(x: point.x - inset, y: point.y), in: session.timeline,
                                                   metrics: metrics, selected: selectedIDs)
                }
            ) {
                TimelineTracksView(session: session, metrics: metrics, inset: inset, store: store, reordering: reordering,
                                   dropTarget: dropTrack.map { .track($0) }, onAddMedia: onAddMedia)
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

    private var selectedIDs: Set<UUID> {
        Set([session.selectedClipID, session.selectedTextID, session.selectedAudioID].compactMap { $0 })
    }

    /// Long-press a clip, then drag: other clips reflow as the finger passes their midpoints.
    private func reorder(_ state: UIGestureRecognizer.State, trackX: CGFloat, y: CGFloat) {
        let time = metrics.time(forOffset: trackX)
        if !session.timeline.isMagnetic || sliding != nil {
            slide(state, time: time, y: y)
            return
        }
        switch state {
        case .began:
            guard let id = mainClip(at: time, y: y) else { return }
            session.beginInteractiveEdit()
            session.selectedClipID = nil
            reordering = (id, trackX, y)
        case .changed:
            guard let id = reordering?.id else { return }
            reordering = (id, trackX, y)
            dropTrack = videoTrack(atY: y)
            // Over another track the clip just follows the finger; the main track keeps its order.
            guard dropTrack == nil else { return }
            session.updateInteractiveEdit { timeline in
                timeline.moveClip(id, to: timeline.reorderDestination(movingClip: id, toTime: time))
            }
        case .ended, .cancelled, .failed:
            guard let id = reordering?.id else { return }
            if state == .ended, let track = dropTrack, let clip = session.timeline[clip: id] {
                // The clip is drawn centred on the finger.
                let start = time - clip.duration / 2
                session.updateInteractiveEdit { $0.moveToOverlay(id, track: track.id, start: start) }
            }
            reordering = nil
            dropTrack = nil
            Task { await session.endInteractiveEdit() }
        default:
            break
        }
    }

    /// The main-track clip under a long press, if it began on the main row.
    private func mainClip(at time: Double, y: CGFloat) -> Clip.ID? {
        guard !session.isEditingInteractively, TimelineLayout.row(atY: y, in: session.timeline) == .main,
              let index = session.timeline.clipIndex(at: time)
        else { return nil }
        return session.timeline.clips[index].id
    }

    private func videoTrack(atY y: CGFloat) -> Track? {
        guard case .track(let track) = TimelineLayout.row(atY: y, in: session.timeline), track.kind == .video else { return nil }
        return track
    }

    /// Magnet off: long-press a clip, then drag it along the track (it stops at
    /// its neighbours) or down onto a video track.
    private func slide(_ state: UIGestureRecognizer.State, time: Double, y: CGFloat) {
        switch state {
        case .began:
            guard let id = mainClip(at: time, y: y) else { return }
            session.beginInteractiveEdit()
            session.selectedClipID = nil
            sliding = (id, time)
        case .changed:
            guard let sliding else { return }
            dropTrack = videoTrack(atY: y)
            let delta = time - sliding.startTime
            session.updateInteractiveEdit { timeline in
                guard let range = timeline.timeRange(ofClip: sliding.id) else { return }
                timeline.slideClip(sliding.id, toStart: range.lowerBound + delta)
            }
        case .ended, .cancelled, .failed:
            guard let sliding else { return }
            if state == .ended, let track = dropTrack {
                let delta = time - sliding.startTime
                session.updateInteractiveEdit { timeline in
                    guard let range = timeline.timeRange(ofClip: sliding.id) else { return }
                    timeline.moveToOverlay(sliding.id, track: track.id, start: range.lowerBound + delta)
                }
            }
            self.sliding = nil
            dropTrack = nil
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
