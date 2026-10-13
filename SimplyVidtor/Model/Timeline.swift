import Foundation

/// The edit itself: clips back to back on one video track, plus audio.
/// Mutations clamp to valid values instead of failing.
nonisolated struct Timeline: Codable, Hashable, Sendable {
    var clips: [Clip] = []
    var audioItems: [AudioItem] = []
    var textItems: [TextItem] = []
    var format = ProjectFormat()

    /// `nil` matches the first clip's shape.
    var aspectRatio: AspectRatio? {
        get { format.aspectRatio }
        set { format.aspectRatio = newValue }
    }

    var duration: Double {
        startTime(ofClipAt: clips.count)
    }

    func index(ofClip id: Clip.ID) -> Int? {
        clips.firstIndex { $0.id == id }
    }

    /// How long clip `index` and the next one play together. Never more than
    /// half of either clip, so a transition can't swallow a clip.
    func overlap(afterClipAt index: Int) -> Double {
        guard index >= 0, index + 1 < clips.count, let transition = clips[index].transition else { return 0 }
        return min(transition.duration, clips[index].duration / 2, clips[index + 1].duration / 2)
    }

    /// Start of clip `index`; `clips.count` gives the end of the timeline.
    func startTime(ofClipAt index: Int) -> Double {
        (0..<min(index, clips.count)).reduce(0) { $0 + clips[$1].duration - overlap(afterClipAt: $1) }
    }

    func timeRange(ofClipAt index: Int) -> Range<Double> {
        let start = startTime(ofClipAt: index)
        return start..<(start + clips[index].duration)
    }

    /// The clip playing at `time`. A boundary (or overlap) belongs to the clip
    /// that starts there; the very end belongs to the last clip.
    func clipIndex(at time: Double) -> Int? {
        guard !clips.isEmpty, time >= 0, time <= duration else { return nil }
        for index in clips.indices.dropLast() where time < startTime(ofClipAt: index + 1) {
            return index
        }
        return clips.count - 1
    }

    // MARK: - Editing

    mutating func insert(_ newClips: [Clip], at index: Int) {
        clips.insert(contentsOf: newClips, at: min(max(index, 0), clips.count))
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

    /// Splits the clip under `time`. Returns the id of the new right-hand clip,
    /// or `nil` when either half would be shorter than `Clip.minimumDuration`.
    @discardableResult
    mutating func split(at time: Double) -> Clip.ID? {
        guard canSplit(at: time), let index = clipIndex(at: time) else { return nil }
        let offset = time - startTime(ofClipAt: index)
        let clip = clips[index]

        let sourceOffset = offset * clip.speed
        var right = clip
        right.id = UUID()
        right.sourceStart += sourceOffset
        right.sourceDuration -= sourceOffset
        clips[index].sourceDuration = sourceOffset
        // The right half carries the transition into the next clip.
        clips[index].transition = nil
        clips.insert(right, at: index + 1)
        return right.id
    }

    /// Moves the clip's in-point, keeping its out-point fixed.
    mutating func trimStart(ofClip id: Clip.ID, toSource newStart: Double) {
        guard let index = index(ofClip: id) else { return }
        let clip = clips[index]
        let latest = clip.sourceEnd - Clip.minimumDuration * clip.speed
        let start = min(max(newStart, 0), latest)
        clips[index].sourceStart = start
        clips[index].sourceDuration = clip.sourceEnd - start
    }

    /// Moves the clip's out-point, keeping its in-point fixed.
    mutating func trimEnd(ofClip id: Clip.ID, toSource newEnd: Double) {
        guard let index = index(ofClip: id) else { return }
        let clip = clips[index]
        let earliest = clip.sourceStart + Clip.minimumDuration * clip.speed
        let end = min(max(newEnd, earliest), clip.mediaDuration ?? .infinity)
        clips[index].sourceDuration = end - clip.sourceStart
    }

    mutating func setSpeed(_ speed: Double, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        // Never let a speed-up push the clip under the minimum length.
        let fastest = min(Clip.speedRange.upperBound, clips[index].sourceDuration / Clip.minimumDuration)
        let range = Clip.speedRange.lowerBound...max(fastest, Clip.speedRange.lowerBound)
        clips[index].speed = min(max(speed, range.lowerBound), range.upperBound)
    }

    mutating func setPreservesPitch(_ preservesPitch: Bool, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].preservesPitch = preservesPitch
    }

    mutating func setVolume(_ volume: Double, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].volume = min(max(volume, Clip.volumeRange.lowerBound), Clip.volumeRange.upperBound)
    }

    mutating func setMuted(_ isMuted: Bool, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].isMuted = isMuted
    }

    mutating func setFilter(_ filter: ClipFilter?, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].filter = filter
    }

    /// Gives every clip the same filter as `id`.
    mutating func applyFilterToAll(from id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        let filter = clips[index].filter
        for i in clips.indices { clips[i].filter = filter }
    }

    mutating func setAdjustment(_ parameter: ClipAdjustments.Parameter, to value: Double, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].adjustments[parameter] = value
    }

    mutating func resetAdjustments(ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].adjustments = ClipAdjustments()
    }

    // MARK: - Audio

    func audioIndex(of id: AudioItem.ID) -> Int? {
        audioItems.firstIndex { $0.id == id }
    }

    /// Replaces the item with the same id, clamping volume and fades.
    mutating func updateAudio(_ item: AudioItem) {
        guard let index = audioIndex(of: item.id) else { return }
        audioItems[index] = item.clampingFades()
    }

    mutating func removeAudio(_ id: AudioItem.ID) {
        audioItems.removeAll { $0.id == id }
    }

    // MARK: - Text

    func textIndex(of id: TextItem.ID) -> Int? {
        textItems.firstIndex { $0.id == id }
    }

    /// Replaces the item with the same id (or adds it), clamping its values.
    mutating func upsertText(_ item: TextItem) {
        var item = item
        item.timelineStart = max(item.timelineStart, 0)
        item.duration = max(item.duration, Clip.minimumDuration)
        item.x = min(max(item.x, 0), 1)
        item.y = min(max(item.y, 0), 1)
        item.size = min(max(item.size, TextItem.sizeRange.lowerBound), TextItem.sizeRange.upperBound)
        if let index = textIndex(of: item.id) {
            textItems[index] = item
        } else {
            textItems.append(item)
        }
    }

    mutating func removeText(_ id: TextItem.ID) {
        textItems.removeAll { $0.id == id }
    }

    /// Turns the clip 90° clockwise, carrying its crop along.
    mutating func rotateClip(_ id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].rotation = (clips[index].rotation + 1) % 4
        clips[index].crop = clips[index].crop?.rotatedClockwise
    }

    /// A full-frame crop is stored as `nil`.
    mutating func setCrop(_ crop: CropRect?, ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        let clamped = crop?.clamped
        clips[index].crop = clamped?.isFull == true ? nil : clamped
    }

    mutating func resetFraming(ofClip id: Clip.ID) {
        guard let index = index(ofClip: id) else { return }
        clips[index].rotation = 0
        clips[index].crop = nil
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

    /// Inserts a copy right after the original. Returns the copy's id.
    @discardableResult
    mutating func duplicateClip(_ id: Clip.ID) -> Clip.ID? {
        guard let index = index(ofClip: id) else { return nil }
        var copy = clips[index]
        copy.id = UUID()
        clips.insert(copy, at: index + 1)
        return copy.id
    }

    mutating func removeClip(_ id: Clip.ID) {
        clips.removeAll { $0.id == id }
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

    /// Moves a clip so it ends up at `destination` in the resulting array.
    mutating func moveClip(_ id: Clip.ID, to destination: Int) {
        guard let index = index(ofClip: id) else { return }
        let clip = clips.remove(at: index)
        clips.insert(clip, at: min(max(destination, 0), clips.count))
    }
}

nonisolated extension Timeline {
    private enum CodingKeys: String, CodingKey {
        case clips, audioItems, textItems, format
        /// Saved before `format`; read only.
        case aspectRatio
    }

    /// Lists and fields added after the first release are decoded leniently.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacyAspect = try c.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio)
        self.init(
            clips: try c.decode([Clip].self, forKey: .clips),
            audioItems: try c.decodeIfPresent([AudioItem].self, forKey: .audioItems) ?? [],
            textItems: try c.decodeIfPresent([TextItem].self, forKey: .textItems) ?? [],
            format: try c.decodeIfPresent(ProjectFormat.self, forKey: .format) ?? ProjectFormat(aspectRatio: legacyAspect)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clips, forKey: .clips)
        try c.encode(audioItems, forKey: .audioItems)
        try c.encode(textItems, forKey: .textItems)
        try c.encode(format, forKey: .format)
    }
}
