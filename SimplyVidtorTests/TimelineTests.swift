import Foundation
import Testing
@testable import SimplyVidtor

struct TimelineTests {
    /// 4 s, 6 s at 2x (3 s on the timeline), photo 3 s: total 10 s.
    private func sample() -> Timeline {
        var fast = Clip.video(mediaFile: "b.mov", duration: 6)
        fast.speed = 2
        return Timeline(clips: [
            .video(mediaFile: "a.mov", duration: 4),
            fast,
            .photo(mediaFile: "c.heic"),
        ])
    }

    // MARK: - Durations and lookup

    @Test func clipDurationIsSourceDurationOverSpeed() {
        var clip = Clip.video(mediaFile: "a.mov", duration: 10)
        clip.speed = 4
        #expect(clip.duration == 2.5)
        #expect(Clip.photo(mediaFile: "p.heic").duration == Clip.defaultPhotoDuration)
    }

    @Test func timelineDurationSumsClipDurations() {
        #expect(sample().duration == 10)
        #expect(Timeline().duration == 0)
    }

    @Test func clipTimeRanges() {
        let timeline = sample()
        #expect(timeline.timeRange(ofClipAt: 0) == 0..<4)
        #expect(timeline.timeRange(ofClipAt: 1) == 4..<7)
        #expect(timeline.timeRange(ofClipAt: 2) == 7..<10)
    }

    @Test(arguments: [
        (0.0, 0), (3.99, 0), (4.0, 1), (6.5, 1), (7.0, 2), (10.0, 2),
    ])
    func clipIndexAtTime(time: Double, expected: Int) {
        #expect(sample().clipIndex(at: time) == expected)
    }

    @Test func clipIndexOutsideTimelineIsNil() {
        #expect(sample().clipIndex(at: -0.1) == nil)
        #expect(sample().clipIndex(at: 10.1) == nil)
        #expect(Timeline().clipIndex(at: 0) == nil)
    }

    // MARK: - Split

    @Test func splitDividesSourceAtTheRightPoint() throws {
        var timeline = sample()
        let split = timeline.split(at: 1.5)
        let newID = try #require(split)

        #expect(timeline.clips.count == 4)
        #expect(timeline.clips[0].sourceStart == 0)
        #expect(timeline.clips[0].sourceDuration == 1.5)
        #expect(timeline.clips[1].id == newID)
        #expect(timeline.clips[1].sourceStart == 1.5)
        #expect(timeline.clips[1].sourceDuration == 2.5)
        #expect(timeline.duration == 10)
    }

    @Test func splitRespectsSpeed() {
        var timeline = sample()
        // 1 s into the 2x clip is 2 s into its source.
        #expect(timeline.split(at: 5) != nil)
        #expect(timeline.clips[1].sourceDuration == 2)
        #expect(timeline.clips[2].sourceStart == 2)
        #expect(timeline.clips[2].sourceDuration == 4)
        #expect(timeline.clips[2].speed == 2)
        #expect(timeline.duration == 10)
    }

    @Test func splitTooCloseToAnEdgeIsRejected() {
        var timeline = sample()
        #expect(timeline.split(at: 0.05) == nil)
        #expect(timeline.split(at: 3.95) == nil)
        #expect(timeline.split(at: 4) == nil) // exactly on a boundary
        #expect(timeline.clips.count == 3)
    }

    @Test func canSplitMatchesSplit() {
        let timeline = sample()
        #expect(timeline.canSplit(at: 1.5))
        #expect(!timeline.canSplit(at: 0.05))
        #expect(!timeline.canSplit(at: 4))
        #expect(!Timeline().canSplit(at: 0))
    }

    @Test(arguments: [
        (0.0, 0), (1.9, 0), // first half of a (0..<4)
        (2.1, 1), (5.4, 1), // second half of a, first half of b (4..<7)
        (5.6, 2), (9.9, 3), // second half of b, second half of c
    ])
    func insertionIndexAtPlayhead(time: Double, expected: Int) {
        #expect(sample().insertionIndex(at: time) == expected)
    }

    // MARK: - Trim

    @Test func trimStartKeepsOutPoint() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.trimStart(ofClip: id, toSource: 1)
        #expect(timeline.clips[0].sourceStart == 1)
        #expect(timeline.clips[0].sourceEnd == 4)
    }

    @Test func trimStartClampsToMediaStartAndMinimumLength() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.trimStart(ofClip: id, toSource: -2)
        #expect(timeline.clips[0].sourceStart == 0)

        timeline.trimStart(ofClip: id, toSource: 10)
        #expect(abs(timeline.clips[0].duration - Clip.minimumDuration) < 1e-9)
        #expect(timeline.clips[0].sourceEnd == 4)
    }

    @Test func trimEndClampsToMediaLength() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.trimEnd(ofClip: id, toSource: 2)
        #expect(timeline.clips[0].sourceDuration == 2)

        timeline.trimEnd(ofClip: id, toSource: 99)
        #expect(timeline.clips[0].sourceEnd == 4)
    }

    @Test func minimumLengthAccountsForSpeed() {
        var timeline = sample()
        let id = timeline.clips[1].id // 2x
        timeline.trimEnd(ofClip: id, toSource: 0)
        #expect(abs(timeline.clips[1].duration - Clip.minimumDuration) < 1e-9)
    }

    @Test func photosCanBeExtendedFreely() {
        var timeline = sample()
        let id = timeline.clips[2].id
        timeline.trimEnd(ofClip: id, toSource: 30)
        #expect(timeline.clips[2].duration == 30)
    }

    // MARK: - Speed

    @Test func speedIsClampedToRange() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.setSpeed(50, ofClip: id)
        #expect(timeline.clips[0].speed == Clip.speedRange.upperBound)
        timeline.setSpeed(0, ofClip: id)
        #expect(timeline.clips[0].speed == Clip.speedRange.lowerBound)
    }

    @Test func speedUpCannotShrinkClipBelowMinimum() {
        var timeline = Timeline(clips: [.video(mediaFile: "a.mov", duration: 0.5)])
        let id = timeline.clips[0].id
        timeline.setSpeed(10, ofClip: id)
        #expect(timeline.clips[0].speed == 5)
        #expect(abs(timeline.clips[0].duration - Clip.minimumDuration) < 1e-9)
    }

    // MARK: - Insert, duplicate, remove, move

    @Test func insertClampsIndex() {
        var timeline = sample()
        let extra = Clip.video(mediaFile: "x.mov", duration: 1)
        timeline.insert([extra], at: 99)
        #expect(timeline.clips.last?.id == extra.id)
        timeline.insert([.photo(mediaFile: "y.heic")], at: -5)
        #expect(timeline.clips.first?.mediaFile == "y.heic")
    }

    @Test func duplicateInsertsCopyAfterOriginal() throws {
        var timeline = sample()
        let original = timeline.clips[1]
        let duplicated = timeline.duplicateClip(original.id)
        let copyID = try #require(duplicated)
        #expect(timeline.clips.count == 4)
        #expect(timeline.clips[2].id == copyID)
        #expect(copyID != original.id)
        #expect(timeline.clips[2].sourceDuration == original.sourceDuration)
        #expect(timeline.clips[2].speed == original.speed)
    }

    @Test func removeClip() {
        var timeline = sample()
        timeline.removeClip(timeline.clips[1].id)
        #expect(timeline.clips.map(\.mediaFile) == ["a.mov", "c.heic"])
        #expect(timeline.duration == 7)
    }

    @Test func moveClip() {
        var timeline = sample()
        timeline.moveClip(timeline.clips[0].id, to: 2)
        #expect(timeline.clips.map(\.mediaFile) == ["b.mov", "c.heic", "a.mov"])
        timeline.moveClip(timeline.clips[2].id, to: 0)
        #expect(timeline.clips.map(\.mediaFile) == ["a.mov", "b.mov", "c.heic"])
    }

    @Test(arguments: [
        (0.5, 0), // before a's midpoint (2): first
        (2.5, 1), // past a's midpoint: after a
        (8.6, 2), // past c's midpoint (8.5): last
    ])
    func reorderDestinationForDraggedMiddleClip(time: Double, expected: Int) {
        let timeline = sample()
        #expect(timeline.reorderDestination(movingClip: timeline.clips[1].id, toTime: time) == expected)
    }

    @Test func reorderDestinationApplied() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.moveClip(id, to: timeline.reorderDestination(movingClip: id, toTime: 9))
        #expect(timeline.clips.map(\.mediaFile) == ["b.mov", "c.heic", "a.mov"])
    }

    @Test func unknownClipIDIsIgnored() {
        var timeline = sample()
        let before = timeline
        timeline.trimStart(ofClip: UUID(), toSource: 1)
        timeline.setSpeed(2, ofClip: UUID())
        timeline.removeClip(UUID())
        timeline.moveClip(UUID(), to: 0)
        #expect(timeline.duplicateClip(UUID()) == nil)
        #expect(timeline == before)
    }

    // MARK: - Codable

    @Test func roundTripsThroughJSON() throws {
        var timeline = sample()
        timeline.audioItems = [AudioItem(mediaFile: "song.m4a", mediaDuration: 30)]
        let data = try JSONEncoder().encode(timeline)
        #expect(try JSONDecoder().decode(Timeline.self, from: data) == timeline)
    }

    @Test func clipsSavedBeforePitchOptionDecodeWithPitchKept() throws {
        let json = """
        {"id":"\(UUID().uuidString)","mediaFile":"a.mov","kind":"video","mediaDuration":2,
         "sourceStart":0,"sourceDuration":2,"speed":2,"volume":1}
        """
        let clip = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
        #expect(clip.preservesPitch)
        #expect(!clip.isMuted)
        #expect(clip.speed == 2)
    }

    @Test func volumeIsClampedAndMuteKeepsIt() {
        var timeline = sample()
        let id = timeline.clips[0].id
        timeline.setVolume(1.5, ofClip: id)
        #expect(timeline.clips[0].volume == 1)
        timeline.setVolume(0.4, ofClip: id)
        timeline.setMuted(true, ofClip: id)
        #expect(timeline.clips[0].effectiveVolume == 0)
        timeline.setMuted(false, ofClip: id)
        #expect(timeline.clips[0].effectiveVolume == 0.4)
    }
}
