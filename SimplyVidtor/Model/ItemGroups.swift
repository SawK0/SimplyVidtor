import Foundation

/// Several items edited at once: clips on any track, text and audio, by id.
nonisolated extension Timeline {
    /// Every item on every track.
    var allItemIDs: Set<UUID> {
        Set(allClips.map(\.id) + textItems.map(\.id) + audioItems.map(\.id))
    }

    /// Where any item plays on the timeline.
    func timeRange(ofItem id: UUID) -> Range<Double>? {
        if let range = timeRange(ofClip: id) { return range }
        if let index = textIndex(of: id) { return textItems[index].timelineStart..<textItems[index].timelineEnd }
        if let index = audioIndex(of: id) { return audioItems[index].timelineStart..<audioItems[index].timelineEnd }
        return nil
    }

    /// Items still playing at or starting after `time`, like Premiere's Track Select Forward.
    func itemIDs(endingAfter time: Double) -> Set<UUID> {
        allItemIDs.filter { (timeRange(ofItem: $0)?.upperBound ?? 0) > time }
    }

    /// Moves the items in time by `delta` seconds, keeping their spacing and
    /// tracks; none goes before 0. Main-track clips push later clips right if
    /// they land on them and lose their transitions, as with `moveMainClip`.
    mutating func moveItems(_ ids: Set<UUID>, by delta: Double) {
        guard let earliest = ids.compactMap({ timeRange(ofItem: $0)?.lowerBound }).min() else { return }
        let delta = max(delta, -earliest)
        guard delta != 0 else { return }

        let moving = clips.indices.filter { ids.contains(clips[$0].id) }
        var lifted: [(clip: Clip, start: Double)] = []
        for index in moving {
            var clip = clips[index]
            clip.transition = nil
            if index > 0 { clips[index - 1].transition = nil }
            lifted.append((clip, startTime(ofClipAt: index) + delta))
        }
        for item in lifted { removeClip(item.clip.id) }
        for item in lifted { place([item.clip], at: item.start) }

        // Shift everything first, so items moving together don't bump each other.
        for index in overlays.indices where ids.contains(overlays[index].id) { overlays[index].timelineStart += delta }
        for index in textItems.indices where ids.contains(textItems[index].id) { textItems[index].timelineStart += delta }
        for index in audioItems.indices where ids.contains(audioItems[index].id) { audioItems[index].timelineStart += delta }
        for index in overlays.indices where ids.contains(overlays[index].id) { settleOverlay(at: index) }
        for index in textItems.indices where ids.contains(textItems[index].id) { settleText(at: index) }
        for index in audioItems.indices where ids.contains(audioItems[index].id) { settleAudio(at: index) }
    }

    /// Removes the items from every track. Other main clips stay put.
    mutating func removeItems(_ ids: Set<UUID>) {
        for id in ids {
            removeClip(id)
            removeText(id)
            removeAudio(id)
        }
    }
}
