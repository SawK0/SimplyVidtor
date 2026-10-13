import Foundation
import Testing
@testable import SimplyVidtor

struct KeyframeTests {
    private func zoom() -> KeyframeTrack<ClipTransform> {
        KeyframeTrack([
            Keyframe(time: 1, value: ClipTransform(scale: 1)),
            Keyframe(time: 3, value: ClipTransform(scale: 1.5)),
        ])
    }

    @Test func valuesBlendBetweenKeyframesAndHoldOutside() {
        let track = zoom()
        #expect(track.value(at: 0)?.scale == 1)
        #expect(abs(track.value(at: 2)!.scale - 1.25) < 1e-9)
        #expect(track.value(at: 9)?.scale == 1.5)
        #expect(KeyframeTrack<ClipTransform>().value(at: 1) == nil)
    }

    @Test func easingShapesTheBlend() {
        var track = zoom()
        track.setEasing(.easeIn, near: 1)
        #expect(track.value(at: 2)!.scale < 1.25)
    }

    @Test func setReplacesNearbyKeyframesAndKeepsOrder() {
        var track = zoom()
        track.set(ClipTransform(scale: 2), at: 3.01)
        #expect(track.times == [1, 3])
        #expect(track.value(at: 3)?.scale == 2)
        track.set(ClipTransform(scale: 3), at: 2)
        #expect(track.times == [1, 2, 3])
        #expect(track.remove(near: 2)?.scale == 3)
        #expect(track.times == [1, 3])
    }

    @Test func previousAndNextSkipTheCurrentKeyframe() {
        let track = zoom()
        #expect(track.next(after: 1)?.time == 3)
        #expect(track.previous(before: 3)?.time == 1)
        #expect(track.previous(before: 1) == nil)
    }

    @Test func transformModeDoesNotBlend() {
        let a = ClipTransform(mode: .fill, x: 0), b = ClipTransform(mode: .fit, x: 1)
        let mid = a.mixed(with: b, 0.5)
        #expect(mid.mode == .fill && mid.x == 0.5)
    }

    @Test func toggleAddsCurrentTransformAndRemovingTheLastKeepsIt() {
        var clip = Clip.video(mediaFile: "a.mov", duration: 4)
        clip.transform.scale = 1.2
        var timeline = Timeline(clips: [clip])
        timeline.toggleTransformKeyframe(ofClip: clip.id, atSource: 0)
        #expect(timeline.clips[0].transformKeyframes.value(at: 0)?.scale == 1.2)

        // With keyframes, editing sets the keyframe at the playhead.
        timeline.setTransform(ClipTransform(scale: 1.5), ofClip: clip.id, atSource: 2)
        #expect(timeline.clips[0].transformKeyframes.times == [0, 2])
        #expect(timeline.clips[0].transform.scale == 1.2, "The static transform is untouched")

        timeline.toggleTransformKeyframe(ofClip: clip.id, atSource: 0)
        timeline.toggleTransformKeyframe(ofClip: clip.id, atSource: 2)
        #expect(timeline.clips[0].transformKeyframes.isEmpty)
        #expect(timeline.clips[0].transform.scale == 1.5, "Keeps the last keyframe's look")
    }

    @Test func keyframesStayOnTheirFramesThroughTrimSplitAndSpeed() throws {
        var clip = Clip.video(mediaFile: "a.mov", duration: 4)
        clip.transformKeyframes = zoom()
        var timeline = Timeline(clips: [clip])
        timeline.trimStart(ofClip: clip.id, toSource: 1)
        timeline.setSpeed(2, ofClip: clip.id)
        // Timeline 0.5 s is now source 2 s: halfway through the zoom.
        let hit = try #require(timeline.clipSourceTime(at: 0.5))
        #expect(abs(timeline.clips[hit.index].transform(atSource: hit.sourceTime).scale - 1.25) < 1e-9)

        let splitID = timeline.split(at: 0.5)
        let right = try #require(splitID)
        let index = try #require(timeline.index(ofClip: right))
        #expect(timeline.clips[index].transformKeyframes == zoom(), "Both halves keep the curve")
    }

    @Test func clipsWithoutKeyframesDecode() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Clip.video(mediaFile: "a.mov", duration: 2))) as! [String: Any]
        json["transformKeyframes"] = nil
        let clip = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(clip.transformKeyframes.isEmpty)

        var keyed = clip
        keyed.transformKeyframes = zoom()
        #expect(try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(keyed)) == keyed)
    }
}
