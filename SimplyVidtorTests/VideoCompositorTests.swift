import AVFoundation
import Foundation
import Testing
@testable import SimplyVidtor

struct VideoCompositorTests {
    let store = MediaStore.temporary()

    private func frame(of output: CompositionBuilder.Output, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: output.composition)
        generator.videoComposition = output.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CompositionBuilder.time(seconds)).image
    }

    private func videoClip() throws -> Clip {
        .video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
    }

    private func soundClip() async throws -> Clip {
        .video(mediaFile: try store.moveIn(try await TestMedia.soundVideoCopy()), duration: 2)
    }

    private func photoClip() throws -> Clip {
        // TestMedia.pngData is filled with (255, 204, 0).
        try MediaImporter.photoClip(writing: TestMedia.pngData(), extension: "png", to: store)
    }

    @Test func photoIsDrawnForItsTimeRange() async throws {
        let output = try await CompositionBuilder.build(Timeline(clips: [try videoClip(), try photoClip()]), store: store)
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 3))
        #expect(color.r > 230 && abs(color.g - 204) < 25 && color.b < 30, "Expected the yellow photo, got \(color)")
    }

    @Test func filterIsAppliedToItsClip() async throws {
        var mono = try photoClip()
        mono.filter = ClipFilter(preset: .mono)
        let output = try await CompositionBuilder.build(Timeline(clips: [mono, try photoClip()]), store: store)
        let filtered = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        let plain = TestMedia.centerColor(of: try await frame(of: output, at: 4))
        #expect(abs(filtered.r - filtered.b) < 10, "Expected gray, got \(filtered)")
        #expect(plain.r - plain.b > 200, "The next clip stays yellow, got \(plain)")
    }

    private func splitPhoto() throws -> Clip {
        try MediaImporter.photoClip(writing: TestMedia.splitPNGData(), extension: "png", to: store)
    }

    @Test func rotationTurnsTheFrameClockwise() async throws {
        var clip = try splitPhoto()
        clip.rotation = 1
        var timeline = Timeline(clips: [clip])
        timeline.aspectRatio = .square
        let image = try await frame(of: try await CompositionBuilder.build(timeline, store: store), at: 1)
        let top = TestMedia.color(of: image, x: 0.5, y: 0.25)
        let bottom = TestMedia.color(of: image, x: 0.5, y: 0.75)
        #expect(top.r > 200 && top.b < 50, "The left (red) half ends up on top, got \(top)")
        #expect(bottom.b > 200 && bottom.r < 50, "Got \(bottom)")
    }

    @Test func cropKeepsOnlyItsRegion() async throws {
        var clip = try splitPhoto()
        clip.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        let image = try await frame(of: try await CompositionBuilder.build(Timeline(clips: [clip]), store: store), at: 1)
        let center = TestMedia.centerColor(of: image)
        #expect(center.r > 200 && center.b < 50, "Only the red half is left, got \(center)")
    }

    /// Yellow photo (3 s) into a missing clip (black), with a 1 s transition from 2 s to 3 s.
    private func fadeToBlank(_ kind: TransitionKind) throws -> Timeline {
        var photo = try photoClip()
        photo.transition = ClipTransition(kind: kind, duration: 1)
        return Timeline(clips: [photo, .video(mediaFile: "gone.mov", duration: 3)])
    }

    @Test func crossfadeBlendsBothClips() async throws {
        let output = try await CompositionBuilder.build(try fadeToBlank(.crossfade), store: store)
        #expect(abs(output.composition.duration.seconds - 5) < 0.02)
        let mid = TestMedia.centerColor(of: try await frame(of: output, at: 2.5))
        // Core Image blends in linear light, so 50% of 255 encodes to about 188.
        #expect((160...215).contains(mid.r), "Halfway between yellow and black, got \(mid)")
        let before = TestMedia.centerColor(of: try await frame(of: output, at: 1.5))
        #expect(before.r > 230)
    }

    @Test func dipToBlackIsBlackAtTheMiddle() async throws {
        let output = try await CompositionBuilder.build(try fadeToBlank(.dipToBlack), store: store)
        let mid = TestMedia.centerColor(of: try await frame(of: output, at: 2.5))
        #expect(mid.r + mid.g + mid.b < 40, "Got \(mid)")
        let quarter = TestMedia.centerColor(of: try await frame(of: output, at: 2.25))
        #expect((160...215).contains(quarter.r), "Half-faded yellow, got \(quarter)")
    }

    @Test func overlappingVideosUseTwoLanes() async throws {
        var first = try await soundClip()
        first.transition = ClipTransition(kind: .crossfade, duration: 0.5)
        let timeline = Timeline(clips: [first, try await soundClip(), try await soundClip()])
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(output.composition.tracks(withMediaType: .video).count == 2)
        #expect(output.composition.tracks(withMediaType: .audio).count == 2)
        #expect(abs(output.composition.duration.seconds - 5.5) < 0.02)
        let transitions = output.videoComposition.instructions.compactMap { ($0 as? ClipInstruction)?.transition }
        #expect(transitions == [.crossfade])
    }

    @Test func textIsDrawnOnlyWhileVisible() async throws {
        // Spaces on a dark box: the frame centre shows the box color.
        var timeline = Timeline(clips: [try photoClip()])
        timeline.textItems = [TextItem(text: "            ", timelineStart: 1, duration: 1, size: 0.3, color: 0x0000FF, background: .box)]
        let output = try await CompositionBuilder.build(timeline, store: store)
        let during = TestMedia.centerColor(of: try await frame(of: output, at: 1.5))
        let after = TestMedia.centerColor(of: try await frame(of: output, at: 2.5))
        #expect(during.b > 200 && during.r < 50, "Expected the blue box, got \(during)")
        #expect(after.r > 230, "Yellow photo again, got \(after)")
    }

    @Test func liveTextChangesShowWithoutRebuilding() async throws {
        let live = LiveStore()
        let output = try await CompositionBuilder.build(Timeline(clips: [try photoClip()]), store: store, live: live)
        live.textItems = [TextItem(text: "            ", timelineStart: 0, size: 0.3, color: 0x0000FF, background: .box)]
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(color.b > 200, "Got \(color)")
    }

    @Test func liveLookChangesShowWithoutRebuilding() async throws {
        let live = LiveStore()
        let clip = try photoClip()
        let output = try await CompositionBuilder.build(Timeline(clips: [clip]), store: store, live: live)
        var look = clip.look
        look.filter = ClipFilter(preset: .mono)
        live.looks[clip.id] = look
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(abs(color.r - color.b) < 10, "Expected the live mono look, got \(color)")
    }

    @Test func videoFrameIsNotBlack() async throws {
        let output = try await CompositionBuilder.build(Timeline(clips: [try videoClip()]), store: store)
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(color.r + color.g + color.b > 100, "Expected video content, got \(color)")
    }

    @Test func missingFileRendersBlack() async throws {
        let output = try await CompositionBuilder.build(Timeline(clips: [.video(mediaFile: "gone.mov", duration: 2)]), store: store)
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(color.r + color.g + color.b < 30)
    }

    @Test func renderSizeComesFromFirstVideo() async throws {
        let withVideo = try await CompositionBuilder.build(Timeline(clips: [try photoClip(), try videoClip()]), store: store)
        #expect(withVideo.videoComposition.renderSize == CGSize(width: 160, height: 90))
        let photosOnly = try await CompositionBuilder.build(Timeline(clips: [try photoClip()]), store: store)
        #expect(photosOnly.videoComposition.renderSize == CompositionBuilder.defaultRenderSize)

        var rotated = try videoClip()
        rotated.rotation = 1
        let turned = try await CompositionBuilder.build(Timeline(clips: [rotated]), store: store)
        #expect(turned.videoComposition.renderSize == CGSize(width: 90, height: 160))
    }

    @Test func aspectRatioSetsCanvasFromTheLongSide() {
        let base = CGSize(width: 1920, height: 1080)
        #expect(CompositionBuilder.renderSize(aspectRatio: nil, firstVideoSize: base) == base)
        #expect(CompositionBuilder.renderSize(aspectRatio: .portrait, firstVideoSize: base) == CGSize(width: 1080, height: 1920))
        #expect(CompositionBuilder.renderSize(aspectRatio: .square, firstVideoSize: base) == CGSize(width: 1920, height: 1920))
        #expect(CompositionBuilder.renderSize(aspectRatio: nil, firstVideoSize: CGSize(width: 101, height: 57)) == CGSize(width: 102, height: 58))
    }

    @Test func instructionsCoverWholeCompositionWithoutGaps() async throws {
        var fast = try videoClip()
        fast.speed = 3
        let audioURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: audioURL, seconds: 9)
        var audio = AudioItem(mediaFile: try store.moveIn(audioURL), mediaDuration: 9)
        audio.timelineStart = 0
        var photo = try photoClip()
        photo.transition = ClipTransition(kind: .crossfade, duration: 0.4)
        let timeline = Timeline(clips: [photo, fast, try videoClip()], audioItems: [audio])

        let output = try await CompositionBuilder.build(timeline, store: store)
        let ranges = output.videoComposition.instructions.map(\.timeRange)
        #expect(ranges.first?.start == .zero)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.end == b.start)
        }
        #expect(ranges.last?.end == output.composition.duration)
        #expect(abs(output.composition.duration.seconds - timeline.duration) < 0.02, "Audio is cut at the video's end")
    }

    @Test(arguments: [
        (CGAffineTransform.identity, CGImagePropertyOrientation.up),
        (CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0), .right),
        (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920), .left),
        (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080), .down),
    ])
    func orientationFromTransform(transform: CGAffineTransform, expected: CGImagePropertyOrientation) {
        #expect(CGImagePropertyOrientation(transform) == expected)
    }
}
