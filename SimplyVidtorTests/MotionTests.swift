import Foundation
import Testing
@testable import SimplyVidtor

struct MotionTests {
    @Test func linearEasingIsIdentityAndCurvesHitTheEnds() {
        #expect(Easing.linear.value(at: 0.3) == 0.3)
        for easing in [Easing.easeIn, .easeOut, .easeInOut, .snappy, .back] {
            #expect(abs(easing.value(at: 0)) < 0.001)
            #expect(abs(easing.value(at: 1) - 1) < 0.001)
        }
        #expect(Easing.easeIn.value(at: 0.5) < 0.5)
        #expect(Easing.easeOut.value(at: 0.5) > 0.5)
        #expect((0...100).map { Easing.back.value(at: Double($0) / 100) }.max()! > 1, "Back overshoots")
    }

    @Test func easingDecodesNamesAndPoints() throws {
        let decoded = try JSONDecoder().decode([Easing].self, from: Data(#"["easeOut", [0.1, 0.2, 0.3, 0.4]]"#.utf8))
        #expect(decoded == [.easeOut, Easing(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Easing.self, from: Data(#""wobbly""#.utf8)) }
    }

    @Test func keyframesInterpolateWithTheirEasing() {
        let animation = MotionAnimation(id: "t.a", name: "A", roles: [.entrance], keyframes: [
            MotionKeyframe(time: 0, opacity: 0, offsetY: 0.2),
            MotionKeyframe(time: 0.5, opacity: 1, offsetY: 0, easing: .easeIn),
            MotionKeyframe(time: 1, scale: 2),
        ])
        let quarter = animation.state(at: 0.25)
        #expect(abs(quarter.opacity - 0.5) < 1e-9)
        #expect(abs(quarter.offsetY - 0.1) < 1e-9)
        #expect(animation.state(at: 0.75).scale < 1.5, "Eased in, so less than halfway")
        #expect(animation.state(at: 1).scale == 2)
        #expect(animation.state(at: -1).opacity == 0)
    }

    @Test func keyframeDefaultsFillMissingJSONValues() throws {
        let frame = try JSONDecoder().decode(MotionKeyframe.self, from: Data(#"{"time": 0.5, "opacity": 0}"#.utf8))
        #expect(frame == MotionKeyframe(time: 0.5, opacity: 0))
    }

    @Test func exitPlaysTheEntranceBackwards() {
        let fade = AppliedMotion(MotionPresets.fade, role: .exit)
        #expect(fade.state(at: 0, role: .exit).opacity == 1)
        #expect(fade.state(at: 1, role: .exit).opacity == 0)
    }

    @Test func directionTurnsOffsetsAndExitsKeepTravelling() {
        var slide = AppliedMotion(MotionPresets.slide, role: .entrance)
        slide.direction = .right
        let start = slide.state(at: 0, role: .entrance)
        #expect(start.offsetX < 0 && abs(start.offsetY) < 1e-9, "Enters from the left travelling right")
        let end = slide.state(at: 1, role: .exit)
        #expect(end.offsetX > 0, "Leaves to the right")
        slide.direction = .up
        #expect(slide.state(at: 0, role: .entrance).offsetY > 0, "Enters from below travelling up")
    }

    @Test func strengthScalesMovementButNotOpacity() {
        var slide = AppliedMotion(MotionPresets.slide, role: .entrance)
        let normal = slide.state(at: 0, role: .entrance)
        slide.strength = 2
        let strong = slide.state(at: 0, role: .entrance)
        #expect(abs(strong.offsetY - normal.offsetY * 2) < 1e-9)
        #expect(strong.opacity == normal.opacity)
        var spin = AppliedMotion(MotionPresets.spinLoop, role: .loop)
        spin.strength = 0.5
        #expect(abs(spin.state(at: 1, role: .loop).rotation - 2 * .pi) < 1e-9, "Full spins ignore strength")
    }

    @Test func entranceExitAndLoopPlayInTheirWindows() {
        var motion = TextMotion()
        motion[.entrance] = AppliedMotion(MotionPresets.fade, role: .entrance)
        motion[.exit] = AppliedMotion(MotionPresets.zoom, role: .exit)
        motion[.loop] = AppliedMotion(MotionPresets.pulse, role: .loop)
        let duration = 4.0
        #expect(motion.active(at: 0.1, duration: duration).first?.role == .entrance)
        #expect(motion.active(at: 2, duration: duration).first?.role == .loop)
        #expect(motion.active(at: 3.9, duration: duration).first?.role == .exit)
        #expect(motion.state(at: 0, duration: duration).opacity == 0)
        #expect(motion.state(at: 4, duration: duration).opacity == 0)
        // The loop starts at rest right after the entrance.
        #expect(abs(motion.state(at: 0.6, duration: duration).scale - 1) < 1e-6)
    }

    @Test func entranceAndExitShrinkToFitShortItems() {
        var motion = TextMotion()
        motion[.entrance] = AppliedMotion(MotionPresets.fade, role: .entrance)
        motion[.exit] = AppliedMotion(MotionPresets.fade, role: .exit)
        let windows = motion.windows(duration: 0.6)
        #expect(abs(windows.entrance - 0.3) < 1e-9 && abs(windows.exit - 0.3) < 1e-9)
    }

    @Test func appliedMotionIsClamped() {
        var applied = AppliedMotion(MotionPresets.fade, role: .entrance)
        applied.duration = 99
        applied.strength = -1
        var motion = TextMotion()
        motion[.entrance] = applied
        #expect(motion.entrance?.duration == AppliedMotion.durationRange.upperBound)
        #expect(motion.entrance?.strength == AppliedMotion.strengthRange.lowerBound)
    }

    @Test func presetsEndAtRestAndLoopsLineUp() {
        for animation in MotionPresets.all {
            if animation.roles.contains(.entrance) {
                #expect(animation.state(at: 1).isIdentity, "\(animation.id) should end at rest")
            }
            if animation.roles.contains(.loop) {
                let start = animation.state(at: 0), end = animation.state(at: 1)
                #expect(start.opacity == end.opacity && start.scale == end.scale && start.offsetY == end.offsetY,
                        "\(animation.id) should loop smoothly")
            }
        }
        #expect(Set(MotionPresets.all.map(\.id)).count == MotionPresets.all.count)
    }

    @Test func textMotionRoundTripsAndOldTextDecodes() throws {
        var item = TextItem(text: "Hi", timelineStart: 0)
        item.motion[.entrance] = AppliedMotion(MotionPresets.bounce, role: .entrance)
        let decoded = try JSONDecoder().decode(TextItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextItem(text: "Old", timelineStart: 0))) as! [String: Any]
        json["motion"] = nil
        let old = try JSONDecoder().decode(TextItem.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.motion.isEmpty)
    }
}
