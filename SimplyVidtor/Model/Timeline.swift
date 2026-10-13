import Foundation

/// The edit itself: the main video track (`clips`), overlay clips, text and
/// audio on their tracks. Mutations clamp to valid values instead of failing.
nonisolated struct Timeline: Codable, Hashable, Sendable {
    /// The main track. With the magnet on, clips play back to back.
    var clips: [Clip] = []
    var overlays: [OverlayClip] = []
    var audioItems: [AudioItem] = []
    var textItems: [TextItem] = []
    /// Visual tracks in drawing order (bottom to top), and audio tracks.
    var tracks: [Track] = Track.defaults
    /// On: main-track clips stay back to back. Off: clips keep gaps (`Clip.gapBefore`).
    var isMagnetic = true
    var format = ProjectFormat()

    /// `nil` matches the first clip's shape.
    var aspectRatio: AspectRatio? {
        get { format.aspectRatio }
        set { format.aspectRatio = newValue }
    }

    /// The project runs until its last clip, overlay, audio or text ends.
    var duration: Double {
        let ends = audioItems.map(\.timelineEnd) + textItems.map(\.timelineEnd) + overlays.map(\.timelineEnd)
        return max(videoDuration, ends.max() ?? 0)
    }

    /// The end of the main track's last clip.
    var videoDuration: Double {
        startTime(ofClipAt: clips.count)
    }

    func index(ofClip id: Clip.ID) -> Int? {
        clips.firstIndex { $0.id == id }
    }

    /// Empty time before main-track clip `index`; always 0 with the magnet on.
    func gap(beforeClipAt index: Int) -> Double {
        isMagnetic || !clips.indices.contains(index) ? 0 : max(clips[index].gapBefore, 0)
    }

    /// How long clip `index` and the next one play together. Never more than
    /// half of either clip, so a transition can't swallow a clip. Clips with a
    /// gap between them don't overlap.
    func overlap(afterClipAt index: Int) -> Double {
        guard index >= 0, index + 1 < clips.count, let transition = clips[index].transition,
              gap(beforeClipAt: index + 1) == 0
        else { return 0 }
        return min(transition.duration, clips[index].duration / 2, clips[index + 1].duration / 2)
    }

    /// Start of main-track clip `index`; `clips.count` gives the end of the track.
    func startTime(ofClipAt index: Int) -> Double {
        let before = (0..<min(index, clips.count)).reduce(0) {
            $0 + gap(beforeClipAt: $1) + clips[$1].duration - overlap(afterClipAt: $1)
        }
        return before + gap(beforeClipAt: index)
    }

    func timeRange(ofClipAt index: Int) -> Range<Double> {
        let start = startTime(ofClipAt: index)
        return start..<(start + clips[index].duration)
    }

    /// The main-track clip playing at `time`; `nil` in a gap. A boundary (or
    /// overlap) belongs to the clip that starts there; the very end belongs to the last clip.
    func clipIndex(at time: Double) -> Int? {
        guard !clips.isEmpty, time >= 0, time <= videoDuration else { return nil }
        for index in clips.indices.reversed() {
            let range = timeRange(ofClipAt: index)
            guard time >= range.lowerBound else { continue }
            return time < range.upperBound || (index == clips.count - 1 && time <= range.upperBound) ? index : nil
        }
        return nil
    }

    // MARK: - Any clip

    /// A clip on the main track or an overlay track.
    subscript(clip id: Clip.ID) -> Clip? {
        if let index = index(ofClip: id) { return clips[index] }
        return overlayIndex(of: id).map { overlays[$0].clip }
    }

    func isOverlay(_ id: Clip.ID) -> Bool { overlayIndex(of: id) != nil }

    /// Every clip on every track.
    var allClips: [Clip] { clips + overlays.map(\.clip) }

    /// Where a clip plays on the timeline.
    func timeRange(ofClip id: Clip.ID) -> Range<Double>? {
        if let index = index(ofClip: id) { return timeRange(ofClipAt: index) }
        return overlayIndex(of: id).map { overlays[$0].timeRange }
    }

    /// Edits a clip wherever it is. Main-track clips keep later clips in place
    /// with the magnet off; overlays move off anything they now overlap.
    mutating func modifyClip(_ id: Clip.ID, _ body: (inout Clip) -> Void) {
        if let index = index(ofClip: id) {
            let end = timeRange(ofClipAt: index).upperBound
            body(&clips[index])
            keepLaterClipsInPlace(after: index, oldEnd: end)
        } else if let index = overlayIndex(of: id) {
            body(&overlays[index].clip)
            settleOverlay(at: index)
        }
    }

    /// Magnet off: absorbs a change in clip `index`'s end into the gap after it.
    private mutating func keepLaterClipsInPlace(after index: Int, oldEnd: Double) {
        guard !isMagnetic, index + 1 < clips.count else { return }
        let change = oldEnd - timeRange(ofClipAt: index).upperBound
        clips[index + 1].gapBefore = max(gap(beforeClipAt: index + 1) + change, 0)
    }

    // MARK: - Editing

    mutating func insert(_ newClips: [Clip], at index: Int) {
        let index = min(max(index, 0), clips.count)
        var newClips = newClips
        // In a gap, new clips take the gap's place and push the rest right.
        if !isMagnetic, index < clips.count, !newClips.isEmpty {
            newClips[0].gapBefore = clips[index].gapBefore
            clips[index].gapBefore = 0
        }
        clips.insert(contentsOf: newClips, at: index)
    }

    /// Whether `split(at:)` would succeed.
    func canSplit(at time: Double) -> Bool {
        guard let index = clipIndex(at: time) else { return false }
        let offset = time - startTime(ofClipAt: index)
        return offset >= Clip.minimumDuration && clips[index].duration - offset >= Clip.minimumDuration
    }

    /// Where new clips go for a playhead at `time`: before the clip under it if
    /// the playhead is in its first half, otherwise after it.
    func insertionIndex(at time: Double) -> Int {
        for (index, clip) in clips.enumerated() where time < startTime(ofClipAt: index) + clip.duration / 2 {
            return index
        }
        return clips.count
    }

    /// Splits the main-track clip under `time`. Returns the id of the new
    /// right-hand clip, or `nil` when either half would be too short.
    @discardableResult
    mutating func split(at time: Double) -> Clip.ID? {
        guard canSplit(at: time), let index = clipIndex(at: time) else { return nil }
        let offset = time - startTime(ofClipAt: index)
        let (left, right) = Self.halves(of: clips[index], atOffset: offset)
        clips[index] = left
        clips.insert(right, at: index + 1)
        return right.id
    }

    /// Splits clip `id` (main or overlay) at timeline `time`.
    @discardableResult
    mutating func split(clip id: Clip.ID, at time: Double) -> Clip.ID? {
        if index(ofClip: id) != nil { return split(at: time) }
        guard canSplit(clip: id, at: time), let index = overlayIndex(of: id) else { return nil }
        let overlay = overlays[index]
        let (left, right) = Self.halves(of: overlay.clip, atOffset: time - overlay.timelineStart)
        overlays[index].clip = left
        overlays.insert(OverlayClip(clip: right, timelineStart: time, trackID: overlay.trackID), at: index + 1)
        return right.id
    }

    /// Whether `split(clip:at:)` would succeed; a `nil` or main-track clip splits under the playhead.
    func canSplit(clip id: Clip.ID?, at time: Double) -> Bool {
        guard let id, let index = overlayIndex(of: id) else { return canSplit(at: time) }
        let offset = time - overlays[index].timelineStart
        return offset >= Clip.minimumDuration && overlays[index].clip.duration - offset >= Clip.minimumDuration
    }

    private static func halves(of clip: Clip, atOffset offset: Double) -> (Clip, Clip) {
        let sourceOffset = offset * clip.speed
        var left = clip, right = clip
        right.id = UUID()
        right.gapBefore = 0
        right.sourceStart += sourceOffset
        right.sourceDuration -= sourceOffset
        left.sourceDuration = sourceOffset
        // The right half carries the transition into the next clip.
        left.transition = nil
        return (left, right)
    }

    /// Moves the clip's in-point, keeping its out-point fixed. Overlays, and
    /// main clips with the magnet off, keep their end where it is on the timeline.
    mutating func trimStart(ofClip id: Clip.ID, toSource newStart: Double) {
        if let index = index(ofClip: id) {
            let clip = clips[index]
            let latest = clip.sourceEnd - Clip.minimumDuration * clip.speed
            // With the magnet off, a clip can only grow into the gap before it.
            let earliest = isMagnetic ? 0 : max(clip.sourceStart - gap(beforeClipAt: index) * clip.speed, 0)
            let start = min(max(newStart, earliest), latest)
            if !isMagnetic { clips[index].gapBefore = gap(beforeClipAt: index) + (start - clip.sourceStart) / clip.speed }
            clips[index].sourceStart = start
            clips[index].sourceDuration = clip.sourceEnd - start
        } else if let index = overlayIndex(of: id) {
            let overlay = overlays[index]
            let clip = overlay.clip
            let latest = clip.sourceEnd - Clip.minimumDuration * clip.speed
            let earliest = max(clip.sourceStart - overlay.timelineStart * clip.speed, 0)
            let start = min(max(newStart, earliest), latest)
            overlays[index].clip.sourceStart = start
            overlays[index].clip.sourceDuration = clip.sourceEnd - start
            overlays[index].timelineStart += (start - clip.sourceStart) / clip.speed
            settleOverlay(at: index)
        }
    }

    /// Moves the clip's out-point, keeping its in-point fixed.
    mutating func trimEnd(ofClip id: Clip.ID, toSource newEnd: Double) {
        guard let clip = self[clip: id] else { return }
        let earliest = clip.sourceStart + Clip.minimumDuration * clip.speed
        var latest = clip.mediaDuration ?? .infinity
        // With the magnet off, a main clip can only grow into the gap after it.
        if !isMagnetic, let index = index(ofClip: id), index + 1 < clips.count {
            latest = min(latest, clip.sourceEnd + gap(beforeClipAt: index + 1) * clip.speed)
        }
        let end = min(max(newEnd, earliest), latest)
        modifyClip(id) { $0.sourceDuration = end - clip.sourceStart }
    }

    mutating func setSpeed(_ speed: Double, ofClip id: Clip.ID) {
        modifyClip(id) { clip in
            // Never let a speed-up push the clip under the minimum length.
            let fastest = min(Clip.speedRange.upperBound, clip.sourceDuration / Clip.minimumDuration)
            let range = Clip.speedRange.lowerBound...max(fastest, Clip.speedRange.lowerBound)
            clip.speed = min(max(speed, range.lowerBound), range.upperBound)
        }
    }

    mutating func setPreservesPitch(_ preservesPitch: Bool, ofClip id: Clip.ID) {
        modifyClip(id) { $0.preservesPitch = preservesPitch }
    }

    mutating func setVolume(_ volume: Double, ofClip id: Clip.ID) {
        modifyClip(id) { $0.volume = min(max(volume, Clip.volumeRange.lowerBound), Clip.volumeRange.upperBound) }
    }

    mutating func setMuted(_ isMuted: Bool, ofClip id: Clip.ID) {
        modifyClip(id) { $0.isMuted = isMuted }
    }

    mutating func setFilter(_ filter: ClipFilter?, ofClip id: Clip.ID) {
        modifyClip(id) { $0.filter = filter }
    }

    /// Gives every clip, on every track, the same filter as `id`.
    mutating func applyFilterToAll(from id: Clip.ID) {
        guard let filter = self[clip: id].map(\.filter) else { return }
        for i in clips.indices { clips[i].filter = filter }
        for i in overlays.indices { overlays[i].clip.filter = filter }
    }

    mutating func setAdjustment(_ parameter: ClipAdjustments.Parameter, to value: Double, ofClip id: Clip.ID) {
        modifyClip(id) { $0.adjustments[parameter] = value }
    }

    mutating func resetAdjustments(ofClip id: Clip.ID) {
        modifyClip(id) { $0.adjustments = ClipAdjustments() }
    }

    // MARK: - Audio

    func audioIndex(of id: AudioItem.ID) -> Int? {
        audioItems.firstIndex { $0.id == id }
    }

    /// Replaces the item with the same id, clamping volume and fades. It moves
    /// to a free audio track if it overlaps another item.
    mutating func updateAudio(_ item: AudioItem) {
        guard let index = audioIndex(of: item.id) else { return }
        audioItems[index] = item.clampingFades()
        settleAudio(at: index)
    }

    /// Adds audio on the first audio track free for it.
    mutating func addAudio(_ item: AudioItem) {
        var item = item.clampingFades()
        item.trackID = freeTrack(.audio, for: item.timelineStart..<item.timelineEnd,
                                 preferred: audioTracks.first?.id, excluding: item.id)
        audioItems.append(item)
    }

    mutating func removeAudio(_ id: AudioItem.ID) {
        audioItems.removeAll { $0.id == id }
    }

    // MARK: - Text

    func textIndex(of id: TextItem.ID) -> Int? {
        textItems.firstIndex { $0.id == id }
    }

    /// Replaces the item with the same id (or adds it), clamping its values.
    /// It moves to a free text track if it overlaps another item.
    mutating func upsertText(_ item: TextItem) {
        var item = item
        item.timelineStart = max(item.timelineStart, 0)
        item.duration = max(item.duration, Clip.minimumDuration)
        item.x = min(max(item.x, 0), 1)
        item.y = min(max(item.y, 0), 1)
        item.size = min(max(item.size, TextItem.sizeRange.lowerBound), TextItem.sizeRange.upperBound)
        if track(item.trackID)?.kind != .text { item.trackID = tracks.first { $0.kind == .text }?.id ?? addTrack(.text) }
        let index: Int
        if let existing = textIndex(of: item.id) {
            textItems[existing] = item
            index = existing
        } else {
            textItems.append(item)
            index = textItems.count - 1
        }
        settleText(at: index)
    }

    mutating func removeText(_ id: TextItem.ID) {
        textItems.removeAll { $0.id == id }
    }

    // MARK: - Transform

    /// Sets the clip's transform. With keyframes, sets the keyframe at
    /// `sourceTime` instead (adding one if needed).
    mutating func setTransform(_ transform: ClipTransform, ofClip id: Clip.ID, atSource sourceTime: Double? = nil) {
        modifyClip(id) { clip in
            if let sourceTime, !clip.transformKeyframes.isEmpty {
                clip.transformKeyframes.set(transform.clamped, at: sourceTime)
            } else {
                clip.transform = transform.clamped
            }
        }
    }

    /// Adds a keyframe holding the current transform at `sourceTime`, or removes
    /// the one there. Removing the last keyframe keeps its transform.
    mutating func toggleTransformKeyframe(ofClip id: Clip.ID, atSource sourceTime: Double) {
        modifyClip(id) { clip in
            if let removed = clip.transformKeyframes.remove(near: sourceTime) {
                if clip.transformKeyframes.isEmpty { clip.transform = removed }
            } else {
                clip.transformKeyframes.set(clip.transform(atSource: sourceTime), at: sourceTime)
            }
        }
    }

    mutating func setTransformEasing(_ easing: Easing, ofClip id: Clip.ID, atSource sourceTime: Double) {
        modifyClip(id) { $0.transformKeyframes.setEasing(easing, near: sourceTime) }
    }

    /// Clears keyframes and restores the default transform (overlays: their smaller default size).
    mutating func resetTransform(ofClip id: Clip.ID) {
        let isOverlay = isOverlay(id)
        modifyClip(id) { clip in
            clip.transform = ClipTransform()
            if isOverlay { clip.transform.scale = OverlayClip.defaultScale }
            clip.transformKeyframes = KeyframeTrack()
        }
    }

    /// The main-track clip under `time` and the source time there.
    func clipSourceTime(at time: Double) -> (index: Int, sourceTime: Double)? {
        guard let index = clipIndex(at: time) else { return nil }
        return (index, clips[index].sourceTime(atOffset: time - startTime(ofClipAt: index)))
    }

    // MARK: - Framing and transitions

    /// Turns the clip 90° clockwise, carrying its crop along.
    mutating func rotateClip(_ id: Clip.ID) {
        modifyClip(id) { clip in
            clip.rotation = (clip.rotation + 1) % 4
            clip.crop = clip.crop?.rotatedClockwise
        }
    }

    /// A full-frame crop is stored as `nil`.
    mutating func setCrop(_ crop: CropRect?, ofClip id: Clip.ID) {
        let clamped = crop?.clamped
        modifyClip(id) { $0.crop = clamped?.isFull == true ? nil : clamped }
    }

    mutating func resetFraming(ofClip id: Clip.ID) {
        modifyClip(id) { clip in
            clip.rotation = 0
            clip.crop = nil
        }
    }

    mutating func setTransition(_ transition: ClipTransition?, afterClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].transition = transition.map {
            ClipTransition(kind: $0.kind, duration: min(max($0.duration, ClipTransition.durationRange.lowerBound),
                                                         ClipTransition.durationRange.upperBound))
        }
    }

    /// Gives every cut the same transition as the one after `id`.
    mutating func applyTransitionToAll(from id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        let transition = clips[index].transition
        for i in clips.indices.dropLast() { clips[i].transition = transition }
    }

    // MARK: - Arranging

    /// Inserts a copy right after the original (overlays: on the same track if
    /// there's room). Returns the copy's id.
    @discardableResult
    mutating func duplicateClip(_ id: Clip.ID) -> Clip.ID? {
        if let index = index(ofClip: id) {
            var copy = clips[index]
            copy.id = UUID()
            copy.gapBefore = 0
            clips.insert(copy, at: index + 1)
            return copy.id
        }
        guard let index = overlayIndex(of: id) else { return nil }
        var copy = overlays[index]
        copy.clip.id = UUID()
        copy.timelineStart = overlays[index].timelineEnd
        overlays.insert(copy, at: index + 1)
        settleOverlay(at: index + 1)
        return copy.clip.id
    }

    /// Removes a clip from any track. With the magnet off, later main clips stay put.
    mutating func removeClip(_ id: Clip.ID) {
        if let index = index(ofClip: id), !isMagnetic, index + 1 < clips.count {
            let nextStart = startTime(ofClipAt: index + 1)
            let previousEnd = index > 0 ? timeRange(ofClipAt: index - 1).upperBound : 0
            clips[index + 1].gapBefore = max(nextStart - previousEnd, 0)
        }
        clips.removeAll { $0.id == id }
        overlays.removeAll { $0.id == id }
    }

    /// Where a dragged clip should land when the finger is at `time` (in this
    /// timeline's layout): after every other clip whose midpoint is left of it.
    func reorderDestination(movingClip id: Clip.ID, toTime time: Double) -> Int {
        var destination = 0
        for (index, clip) in clips.enumerated() where clip.id != id {
            if startTime(ofClipAt: index) + clip.duration / 2 < time { destination += 1 }
        }
        return destination
    }

    /// Moves a main-track clip so it ends up at `destination` in the resulting array.
    mutating func moveClip(_ id: Clip.ID, to destination: Int) {
        guard let index = index(ofClip: id) else { return }
        let clip = clips.remove(at: index)
        clips.insert(clip, at: min(max(destination, 0), clips.count))
    }
}

nonisolated extension Timeline {
    private enum CodingKeys: String, CodingKey {
        case clips, overlays, audioItems, textItems, tracks, isMagnetic, format
        /// Saved before `format`; read only.
        case aspectRatio
    }

    /// Lists and fields added after the first release are decoded leniently.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyAspect = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
        self.init(
            clips: try c.decode([Clip].self, forKey: .clips),
            overlays: try c.decodeIfPresent([OverlayClip].self, forKey: .overlays) ?? [],
            audioItems: try c.decodeIfPresent([AudioItem].self, forKey: .audioItems) ?? [],
            textItems: try c.decodeIfPresent([TextItem].self, forKey: .textItems) ?? [],
            tracks: try c.decodeIfPresent([Track].self, forKey: .tracks) ?? Track.defaults,
            isMagnetic: try c.decodeIfPresent(Bool.self, forKey: .isMagnetic) ?? true,
            format: try c.decodeIfPresent(ProjectFormat.self, forKey: .format) ?? ProjectFormat(aspectRatio: legacyAspect)
        )
        repairTracks()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clips, forKey: .clips)
        try c.encode(overlays, forKey: .overlays)
        try c.encode(audioItems, forKey: .audioItems)
        try c.encode(textItems, forKey: .textItems)
        try c.encode(tracks, forKey: .tracks)
        try c.encode(isMagnetic, forKey: .isMagnetic)
        try c.encode(format, forKey: .format)
    }
}
