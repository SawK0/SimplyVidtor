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

    private func photoClip() throws -> Clip {
        // TestMedia.pngData is filled with (255, 204, 0).
        try MediaImporter.photoClip(writing: TestMedia.pngData(), extension: "png", to: store)
    }

    @Test func photoIsDrawnForItsTimeRange() async throws {
        let output = try await CompositionBuilder.build(Timeline(clips: [try videoClip(), try photoClip()]), store: store)
        let color = TestMedia.centerColor(of: try await frame(of: output, at: 3))
        #expect(color.r > 230 && abs(color.g - 204) < 25 && color.b < 30, "Expected the yellow photo, got \(color)")
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
    }

    @Test func instructionsCoverWholeCompositionWithoutGaps() async throws {
        var fast = try videoClip()
        fast.speed = 3
        let audioURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: audioURL, seconds: 9)
        var audio = AudioItem(mediaFile: try store.moveIn(audioURL), mediaDuration: 9)
        audio.timelineStart = 0
        let timeline = Timeline(clips: [try photoClip(), fast, try videoClip()], audioItems: [audio])

        let output = try await CompositionBuilder.build(timeline, store: store)
        let ranges = output.videoComposition.instructions.map(\.timeRange)
        #expect(ranges.first?.start == .zero)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.end == b.start)
        }
        #expect(ranges.last?.end == output.composition.duration)
        #expect(output.composition.duration.seconds > timeline.duration, "Audio runs past the clips")
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
