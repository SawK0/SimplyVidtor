import Foundation
import Testing
@testable import SimplyVidtor

struct ItemGroupTests {
    private func video(_ seconds: Double = 4) -> Clip { .video(mediaFile: "a.mov", duration: seconds) }

    /// Main clips 0..<4 and 4..<8, an overlay at 1, text at 2 and audio at 3.
    private func mixed() -> Timeline {
        var timeline = Timeline(clips: [video(), video()])
        _ = timeline.insertOverlay(video(2), at: 1)
        timeline.upsertText(TextItem(text: "A", timelineStart: 2, duration: 1))
        var audio = AudioItem(mediaFile: "song.m4a", mediaDuration: 2)
        audio.timelineStart = 3
        timeline.addAudio(audio)
        return timeline
    }

    private func starts(_ timeline: Timeline, _ ids: [UUID]) -> [Double] {
        ids.map { timeline.timeRange(ofItem: $0)?.lowerBound ?? -1 }
    }

    @Test func itemsOnEveryTrackMoveTogetherKeepingTheirSpacing() {
        var timeline = mixed()
        let ids = [timeline.clips[1].id, timeline.overlays[0].id, timeline.textItems[0].id, timeline.audioItems[0].id]
        let tracks = (timeline.overlays[0].trackID, timeline.textItems[0].trackID, timeline.audioItems[0].trackID)
        timeline.moveItems(Set(ids), by: 2)
        #expect(starts(timeline, ids) == [6, 3, 4, 5])
        #expect(timeline.timeRange(ofClipAt: 0) == 0..<4, "Unpicked clips stay put")
        #expect((timeline.overlays[0].trackID, timeline.textItems[0].trackID, timeline.audioItems[0].trackID) == tracks)
    }

    @Test func aGroupStopsAtZero() {
        var timeline = mixed()
        let ids = [timeline.overlays[0].id, timeline.textItems[0].id]
        timeline.moveItems(Set(ids), by: -5)
        #expect(starts(timeline, ids) == [0, 1], "The earliest item stops at 0; the spacing holds")
    }

    @Test func mainClipsMovedTogetherPushLaterClipsOnlyIfTheyLandOnThem() {
        var timeline = Timeline(clips: [video(2), video(2), video(2)])
        let ids = timeline.clips.prefix(2).map(\.id)
        let last = timeline.clips[2].id
        timeline.moveItems(Set(ids), by: 1)
        #expect(starts(timeline, ids) == [1, 3])
        #expect(timeline.timeRange(ofClip: last)?.lowerBound == 5, "Pushed right by the second clip")

        timeline.moveItems(Set(ids), by: -1)
        #expect(starts(timeline, ids) == [0, 2])
        #expect(timeline.timeRange(ofClip: last)?.lowerBound == 5, "Pushed clips don't come back; the gap stays")
    }

    @Test func movingMainClipsDropsTheirTransitions() {
        var timeline = Timeline(clips: [video(), video(), video()])
        timeline.setTransition(ClipTransition(kind: .crossfade, duration: 0.5), afterClip: timeline.clips[0].id)
        timeline.setTransition(ClipTransition(kind: .crossfade, duration: 0.5), afterClip: timeline.clips[1].id)
        timeline.moveItems([timeline.clips[1].id], by: 1)
        #expect(timeline.clips.allSatisfy { $0.transition == nil })
    }

    @Test func overlaysOnOneTrackMovingTogetherStayOnIt() {
        var timeline = Timeline(clips: [video(10)])
        let a = timeline.insertOverlay(video(2), at: 0)
        let b = timeline.insertOverlay(video(2), at: 2, track: timeline.overlays[0].trackID)
        let track = timeline.overlays[0].trackID
        timeline.moveItems([a, b], by: 1)
        #expect(starts(timeline, [a, b]) == [1, 3])
        #expect(timeline.overlays.allSatisfy { $0.trackID == track }, "A moving onto B's old spot doesn't hop tracks")
    }

    @Test func selectToEndTakesEverythingStillPlaying() {
        let timeline = mixed()
        let picked = timeline.itemIDs(endingAfter: 3.5)
        #expect(picked == [timeline.clips[1].id, timeline.clips[0].id, timeline.audioItems[0].id])
        #expect(timeline.itemIDs(endingAfter: 0) == timeline.allItemIDs)
    }

    @Test func removingItemsFromEveryTrack() {
        var timeline = mixed()
        let kept = timeline.clips[1].id
        timeline.removeItems([timeline.clips[0].id, timeline.overlays[0].id, timeline.textItems[0].id, timeline.audioItems[0].id])
        #expect(timeline.allItemIDs == [kept])
        #expect(timeline.timeRange(ofClip: kept) == 4..<8, "Later clips stay put")
    }

    @Test func snappingIgnoresTheWholeGroup() {
        let timeline = mixed()
        let times = timeline.snapTimes(excluding: [timeline.clips[1].id, timeline.overlays[0].id])
        #expect(times.sorted() == [0, 0, 2, 3, 3, 4, 5])
    }
}
