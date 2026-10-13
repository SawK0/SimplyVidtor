import Foundation

nonisolated enum TrackKind: String, Codable, CaseIterable, Sendable {
    case video, text, audio
}

/// A row on the timeline above (video, text) or below (audio) the main
/// track. Items refer to their track by id.
nonisolated struct Track: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: TrackKind

    /// Every project has these two; items saved before tracks existed land on them.
    static let firstText = Track(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, kind: .text)
    static let firstAudio = Track(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, kind: .audio)
    static let defaults = [firstText, firstAudio]
}

/// A clip on an overlay video track, placed freely in time and drawn over
/// the main track (picture in picture).
nonisolated struct OverlayClip: Codable, Hashable, Identifiable, Sendable {
    /// Overlays start smaller than the frame so the main track shows around them.
    static let defaultScale = 0.6

    var clip: Clip
    var timelineStart: Double
    var trackID: Track.ID

    var id: Clip.ID { clip.id }
    var timelineEnd: Double { timelineStart + clip.duration }
    var timeRange: Range<Double> { timelineStart..<timelineEnd }
}

nonisolated extension Timeline {
    // MARK: - Tracks

    /// Overlay video and text tracks, bottom to top (drawing order).
    var visualTracks: [Track] { tracks.filter { $0.kind != .audio } }
    var audioTracks: [Track] { tracks.filter { $0.kind == .audio } }

    func track(_ id: Track.ID) -> Track? {
        tracks.first { $0.id == id }
    }

    /// Time ranges of the items on a track, apart from `excluding`.
    func ranges(onTrack id: Track.ID, excluding: UUID? = nil) -> [Range<Double>] {
        guard let kind = track(id)?.kind else { return [] }
        switch kind {
        case .video:
            return overlays.filter { $0.trackID == id && $0.id != excluding }.map(\.timeRange)
        case .text:
            return textItems.filter { $0.trackID == id && $0.id != excluding }.map { $0.timelineStart..<$0.timelineEnd }
        case .audio:
            return audioItems.filter { $0.trackID == id && $0.id != excluding }.map { $0.timelineStart..<$0.timelineEnd }
        }
    }

    func isFree(_ trackID: Track.ID, for range: Range<Double>, excluding: UUID? = nil) -> Bool {
        let epsilon = 1e-6
        return !ranges(onTrack: trackID, excluding: excluding).contains {
            $0.lowerBound < range.upperBound - epsilon && range.lowerBound < $0.upperBound - epsilon
        }
    }

    /// `preferred` if it's free for `range`, else the nearest free track of the
    /// same kind, else a new track (just above `preferred`, or on top).
    mutating func freeTrack(_ kind: TrackKind, for range: Range<Double>, preferred: Track.ID?, excluding: UUID?) -> Track.ID {
        let candidates = tracks.indices.filter { tracks[$0].kind == kind }
        let preferredIndex = preferred.flatMap { id in tracks.firstIndex { $0.id == id && $0.kind == kind } }
        let ordered = preferredIndex.map { p in candidates.sorted { abs($0 - p) < abs($1 - p) || (abs($0 - p) == abs($1 - p) && $0 > $1) } }
            ?? candidates
        if let free = ordered.first(where: { isFree(tracks[$0].id, for: range, excluding: excluding) }) {
            return tracks[free].id
        }
        return addTrack(kind, above: preferred)
    }

    /// Adds an empty track and returns its id. Overlay video tracks go just
    /// above `above` (or below the text tracks); text tracks go on top;
    /// audio tracks go at the bottom.
    @discardableResult
    mutating func addTrack(_ kind: TrackKind, above: Track.ID? = nil) -> Track.ID {
        let new = Track(kind: kind)
        if let above, let index = tracks.firstIndex(where: { $0.id == above }), kind != .audio {
            tracks.insert(new, at: index + 1)
        } else if kind == .video, let firstText = tracks.firstIndex(where: { $0.kind == .text }) {
            tracks.insert(new, at: firstText)
        } else if kind == .audio || tracks.lastIndex(where: { $0.kind != .audio }) == nil {
            tracks.append(new)
        } else {
            tracks.insert(new, at: tracks.lastIndex { $0.kind != .audio }! + 1)
        }
        return new.id
    }

    /// Removes a track and everything on it. The last text and audio tracks stay.
    mutating func removeTrack(_ id: Track.ID) {
        guard let track = track(id), canRemoveTrack(id) else { return }
        switch track.kind {
        case .video: overlays.removeAll { $0.trackID == id }
        case .text: textItems.removeAll { $0.trackID == id }
        case .audio: audioItems.removeAll { $0.trackID == id }
        }
        tracks.removeAll { $0.id == id }
    }

    func canRemoveTrack(_ id: Track.ID) -> Bool {
        guard let kind = track(id)?.kind else { return false }
        return kind == .video || tracks.filter { $0.kind == kind }.count > 1
    }

    /// Moves a visual track one step up or down in the drawing order.
    mutating func moveTrack(_ id: Track.ID, up: Bool) {
        guard let index = tracks.firstIndex(where: { $0.id == id }), tracks[index].kind != .audio else { return }
        let visual = tracks.indices.filter { tracks[$0].kind != .audio }
        guard let position = visual.firstIndex(of: index) else { return }
        let target = position + (up ? 1 : -1)
        guard visual.indices.contains(target) else { return }
        tracks.swapAt(index, visual[target])
    }

    /// Gives every item a track of its kind, adding the default tracks when missing.
    mutating func repairTracks() {
        for track in Track.defaults where !tracks.contains(where: { $0.kind == track.kind }) {
            tracks.append(track)
        }
        func fallback(_ kind: TrackKind) -> Track.ID {
            if let existing = tracks.first(where: { $0.kind == kind }) { return existing.id }
            return addTrack(kind)
        }
        for i in textItems.indices where track(textItems[i].trackID)?.kind != .text {
            textItems[i].trackID = fallback(.text)
        }
        for i in audioItems.indices where track(audioItems[i].trackID)?.kind != .audio {
            audioItems[i].trackID = fallback(.audio)
        }
        for i in overlays.indices where track(overlays[i].trackID)?.kind != .video {
            overlays[i].trackID = fallback(.video)
        }
    }

    // MARK: - Overlays

    func overlayIndex(of id: Clip.ID) -> Int? {
        overlays.firstIndex { $0.id == id }
    }

    /// Places a clip on the first overlay track free at `time` (adding one if needed).
    @discardableResult
    mutating func insertOverlay(_ clip: Clip, at time: Double) -> Clip.ID {
        var clip = clip
        clip.transform.scale = OverlayClip.defaultScale
        let start = max(time, 0)
        let preferred = tracks.first { $0.kind == .video }?.id
        let trackID = freeTrack(.video, for: start..<(start + clip.duration), preferred: preferred, excluding: nil)
        overlays.append(OverlayClip(clip: clip, timelineStart: start, trackID: trackID))
        return clip.id
    }

    /// Moves an overlay in time and, optionally, to another video track. If it
    /// lands on another item it hops to the nearest free track.
    mutating func moveOverlay(_ id: Clip.ID, toStart start: Double, track trackID: Track.ID? = nil) {
        guard let index = overlayIndex(of: id) else { return }
        overlays[index].timelineStart = max(start, 0)
        if let trackID, track(trackID)?.kind == .video { overlays[index].trackID = trackID }
        settleOverlay(at: index)
    }

    /// Moves an item off any item it now overlaps on its track.
    mutating func settleOverlay(at index: Int) {
        let overlay = overlays[index]
        overlays[index].trackID = freeTrack(.video, for: overlay.timeRange, preferred: overlay.trackID, excluding: overlay.id)
    }

    mutating func settleText(at index: Int) {
        let item = textItems[index]
        textItems[index].trackID = freeTrack(.text, for: item.timelineStart..<item.timelineEnd, preferred: item.trackID, excluding: item.id)
    }

    mutating func settleAudio(at index: Int) {
        let item = audioItems[index]
        audioItems[index].trackID = freeTrack(.audio, for: item.timelineStart..<item.timelineEnd, preferred: item.trackID, excluding: item.id)
    }

    /// Moves a text item to another text track, hopping on if that spot is taken.
    mutating func moveText(_ id: TextItem.ID, toTrack trackID: Track.ID) {
        guard let index = textIndex(of: id), track(trackID)?.kind == .text else { return }
        textItems[index].trackID = trackID
        settleText(at: index)
    }

    mutating func moveAudio(_ id: AudioItem.ID, toTrack trackID: Track.ID) {
        guard let index = audioIndex(of: id), track(trackID)?.kind == .audio else { return }
        audioItems[index].trackID = trackID
        settleAudio(at: index)
    }

    // MARK: - Magnet

    /// Turning the magnet on closes the gaps between main-track clips.
    mutating func setMagnetic(_ on: Bool) {
        isMagnetic = on
        if on { for i in clips.indices { clips[i].gapBefore = 0 } }
    }

    /// Magnet off: slides a main-track clip in time, between its neighbours.
    mutating func slideClip(_ id: Clip.ID, toStart time: Double) {
        guard !isMagnetic, let index = index(ofClip: id) else { return }
        let start = startTime(ofClipAt: index)
        let earliest = start - gap(beforeClipAt: index)
        let latest = index + 1 < clips.count ? start + gap(beforeClipAt: index + 1) : .infinity
        let delta = min(max(time, earliest), latest) - start
        clips[index].gapBefore = gap(beforeClipAt: index) + delta
        if index + 1 < clips.count { clips[index + 1].gapBefore = gap(beforeClipAt: index + 1) - delta }
    }
}
