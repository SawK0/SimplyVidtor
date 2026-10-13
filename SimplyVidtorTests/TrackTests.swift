import Foundation
import Testing
@testable import SimplyVidtor

struct TrackTests {
    private func video(_ seconds: Double = 4) -> Clip { .video(mediaFile: "a.mov", duration: seconds) }

    // MARK: - Tracks

    @Test func projectsSavedBeforeTracksGetTheDefaults() throws {
        let json = #"{"clips":[],"textItems":[{"id":"\#(UUID())","text":"Hi","timelineStart":0,"duration":3,"x":0.5,"y":0.5,"size":0.1,"rotation":0,"font":"system","color":16777215,"background":"none"}]}"#
        let timeline = try JSONDecoder().decode(Timeline.self, from: Data(json.utf8))
        #expect(timeline.tracks == Track.defaults)
        #expect(timeline.textItems[0].trackID == Track.firstText.id)
        #expect(timeline.isMagnetic && timeline.overlays.isEmpty)
    }

    @Test func itemsOnMissingTracksAreRepaired() throws {
        var timeline = Timeline()
        var item = TextItem(text: "Hi", timelineStart: 0)
        item.trackID = UUID()
        timeline.textItems = [item]
        let decoded = try JSONDecoder().decode(Timeline.self, from: JSONEncoder().encode(timeline))
        #expect(decoded.textItems[0].trackID == Track.firstText.id)
    }

    @Test func newTracksGoInDrawingOrder() {
        var timeline = Timeline()
        let overlay = timeline.addTrack(.video)
        let text = timeline.addTrack(.text)
        let audio = timeline.addTrack(.audio)
        #expect(timeline.visualTracks.map(\.id) == [overlay, Track.firstText.id, text], "Video under text, new text on top")
        #expect(timeline.audioTracks.map(\.id) == [Track.firstAudio.id, audio])
        timeline.moveTrack(overlay, up: true)
        #expect(timeline.visualTracks.map(\.id) == [Track.firstText.id, overlay, text])
    }

    @Test func removingATrackRemovesItsItemsButKeepsTheLastTextTrack() {
        var timeline = Timeline()
        timeline.upsertText(TextItem(text: "A", timelineStart: 0))
        #expect(!timeline.canRemoveTrack(Track.firstText.id))
        let id = timeline.insertOverlay(video(), at: 0)
        let trackID = timeline.overlays[0].trackID
        timeline.removeTrack(trackID)
        #expect(timeline[clip: id] == nil && timeline.track(trackID) == nil)
    }

    @Test func overlappingTextAndAudioMoveToANewTrack() {
        var timeline = Timeline()
        timeline.upsertText(TextItem(text: "A", timelineStart: 0, duration: 3))
        timeline.upsertText(TextItem(text: "B", timelineStart: 3, duration: 3))
        #expect(timeline.textItems.allSatisfy { $0.trackID == Track.firstText.id }, "Back to back fits on one track")
        timeline.upsertText(TextItem(text: "C", timelineStart: 1, duration: 1))
        #expect(timeline.visualTracks.count == 2 && timeline.textItems[2].trackID != Track.firstText.id)

        timeline.addAudio(AudioItem(mediaFile: "a.m4a", mediaDuration: 5))
        timeline.addAudio(AudioItem(mediaFile: "b.m4a", mediaDuration: 5))
        #expect(timeline.audioTracks.count == 2)
        #expect(timeline.audioItems[0].trackID != timeline.audioItems[1].trackID)
    }

    @Test func movingTextOntoAnotherItemHopsToAFreeTrack() {
        var timeline = Timeline()
        timeline.upsertText(TextItem(text: "A", timelineStart: 0, duration: 2))
        let upper = timeline.addTrack(.text)
        let b = TextItem(text: "B", timelineStart: 0, duration: 2)
        timeline.upsertText(b)
        #expect(timeline.textItems[1].trackID == upper)
        timeline.moveText(b.id, toTrack: Track.firstText.id)
        #expect(timeline.textItems[1].trackID == upper, "The first track is taken there")
    }

    // MARK: - Overlays

    @Test func overlaysStackOnNewVideoTracksAndStartSmaller() {
        var timeline = Timeline(clips: [video()])
        let a = timeline.insertOverlay(video(2), at: 1)
        let b = timeline.insertOverlay(video(2), at: 2)
        #expect(timeline.overlays.map(\.trackID).count == 2)
        #expect(timeline.overlays[0].trackID != timeline.overlays[1].trackID)
        #expect(timeline[clip: a]?.transform.scale == OverlayClip.defaultScale)
        #expect(timeline.timeRange(ofClip: b) == 2..<4)
        #expect(timeline.visualTracks.first?.kind == .video, "Overlay tracks sit under text")
        timeline.overlays[1].timelineStart = 20
        #expect(timeline.duration == 22, "Overlays count toward the project length")
    }

    @Test func clipToolsWorkOnOverlays() {
        var timeline = Timeline(clips: [video()])
        let id = timeline.insertOverlay(video(), at: 0)
        timeline.setFilter(ClipFilter(preset: .mono), ofClip: id)
        timeline.setSpeed(2, ofClip: id)
        #expect(timeline[clip: id]?.filter?.preset == .mono)
        #expect(timeline.timeRange(ofClip: id) == 0..<2)
        timeline.resetTransform(ofClip: id)
        #expect(timeline[clip: id]?.transform.scale == OverlayClip.defaultScale)
    }

    @Test func overlayTrimSplitDuplicateAndRemove() throws {
        var timeline = Timeline()
        let id = timeline.insertOverlay(video(4), at: 2)
        timeline.trimStart(ofClip: id, toSource: 1)
        #expect(timeline.timeRange(ofClip: id) == 3..<6, "The end stays put")
        timeline.trimEnd(ofClip: id, toSource: 3)
        #expect(timeline.timeRange(ofClip: id) == 3..<5)

        #expect(timeline.canSplit(clip: id, at: 4))
        let splitID = timeline.split(clip: id, at: 4)
        let right = try #require(splitID)
        #expect(timeline.timeRange(ofClip: id) == 3..<4 && timeline.timeRange(ofClip: right) == 4..<5)

        let copyID = timeline.duplicateClip(right)
        let copy = try #require(copyID)
        #expect(timeline.timeRange(ofClip: copy) == 5..<6)
        #expect(timeline.overlays.allSatisfy { $0.trackID == timeline.overlays[0].trackID }, "Room on the same track")
        timeline.removeClip(copy)
        #expect(timeline[clip: copy] == nil)
    }

    @Test func slowingAnOverlayIntoItsNeighbourMovesIt() {
        var timeline = Timeline()
        let a = timeline.insertOverlay(video(2), at: 0)
        timeline.insertOverlay(video(2), at: 2)
        #expect(timeline.overlays[0].trackID == timeline.overlays[1].trackID)
        timeline.setSpeed(0.5, ofClip: a)
        #expect(timeline.overlays[0].trackID != timeline.overlays[1].trackID)
    }

    // MARK: - Magnet

    private func unmagnetized() -> Timeline {
        var timeline = Timeline(clips: [video(2), video(2), video(2)])
        timeline.setMagnetic(false)
        return timeline
    }

    /// Slides the last clip to 5 s, then the middle one to 3 s: gaps at 2...3 and 5...5.
    private func spaced() -> Timeline {
        var timeline = unmagnetized()
        timeline.slideClip(timeline.clips[2].id, toStart: 5)
        timeline.slideClip(timeline.clips[1].id, toStart: 3)
        return timeline
    }

    @Test func slidingAClipLeavesAGapAndKeepsLaterClips() {
        var timeline = spaced()
        #expect(timeline.timeRange(ofClipAt: 1) == 3..<5)
        #expect(timeline.timeRange(ofClipAt: 2) == 5..<7)
        timeline.slideClip(timeline.clips[1].id, toStart: 9)
        #expect(timeline.timeRange(ofClipAt: 1) == 3..<5, "Can't slide into the next clip")
        timeline.slideClip(timeline.clips[1].id, toStart: 0)
        #expect(timeline.timeRange(ofClipAt: 1) == 2..<4, "Nor into the previous one")
        #expect(timeline.clipIndex(at: 4.5) == nil, "Nothing plays in the gap")
        #expect(timeline.videoDuration == 7)
    }

    @Test func gapsBlockTransitions() {
        var timeline = unmagnetized()
        timeline.setTransition(ClipTransition(kind: .crossfade, duration: 0.5), afterClip: timeline.clips[1].id)
        #expect(timeline.overlap(afterClipAt: 1) == 0.5)
        timeline.slideClip(timeline.clips[2].id, toStart: 6)
        #expect(timeline.overlap(afterClipAt: 1) == 0)
    }

    @Test func magnetOffEditsKeepLaterClipsInPlace() {
        var timeline = unmagnetized()
        let first = timeline.clips[0].id
        timeline.trimEnd(ofClip: first, toSource: 1)
        #expect(timeline.timeRange(ofClipAt: 1) == 2..<4, "Trimming the end leaves a gap")
        timeline.setSpeed(0.5, ofClip: first)
        #expect(timeline.timeRange(ofClipAt: 0) == 0..<2 && timeline.timeRange(ofClipAt: 1) == 2..<4)
        timeline.trimStart(ofClip: timeline.clips[1].id, toSource: 1)
        #expect(timeline.timeRange(ofClipAt: 1) == 3..<4, "Trimming the start keeps the end")
        timeline.removeClip(timeline.clips[1].id)
        #expect(timeline.timeRange(ofClipAt: 1) == 4..<6, "Deleting leaves the gap")
    }

    @Test func magnetOnClosesGaps() {
        var timeline = spaced()
        timeline.setMagnetic(true)
        #expect(timeline.timeRange(ofClipAt: 1) == 2..<4)
        #expect(timeline.clips.allSatisfy { $0.gapBefore == 0 })
    }

    @Test func insertingIntoAGapPushesLaterClips() {
        var timeline = spaced()
        timeline.insert([video(1)], at: 1)
        #expect(timeline.timeRange(ofClipAt: 1) == 3..<4, "Takes the gap's place")
        #expect(timeline.timeRange(ofClipAt: 2) == 4..<6)
    }
}
