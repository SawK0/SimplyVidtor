import AVFoundation
import Foundation
import Testing
@testable import SimplyVidtor

struct OverlayRenderingTests {
    let store = MediaStore.temporary()

    private func frame(of output: CompositionBuilder.Output, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: output.composition)
        generator.videoComposition = output.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CompositionBuilder.time(seconds)).image
    }

    /// TestMedia.pngData is filled with (255, 204, 0).
    private func yellowPhoto() throws -> Clip {
        try MediaImporter.photoClip(writing: TestMedia.pngData(), extension: "png", to: store)
    }

    private func videoClip() throws -> Clip {
        .video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
    }

    private func blueBox(at start: Double = 0) -> TextItem {
        TextItem(text: "      ", timelineStart: start, duration: 3, size: 0.2, color: 0x0000FF, background: .box)
    }

    @Test func overlayPhotoIsDrawnOnlyForItsTime() async throws {
        var timeline = Timeline()
        timeline.insertOverlay(try yellowPhoto(), at: 1)
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(abs(output.composition.duration.seconds - 4) < 0.02, "The project runs to the overlay's end")
        let during = TestMedia.centerColor(of: try await frame(of: output, at: 2))
        let before = TestMedia.centerColor(of: try await frame(of: output, at: 0.5))
        #expect(during.r > 230 && during.b < 30, "Yellow overlay, got \(during)")
        #expect(before.r < 20, "Black before it, got \(before)")
    }

    @Test func higherTracksDrawOnTop() async throws {
        var timeline = Timeline(clips: [try yellowPhoto()])
        timeline.upsertText(blueBox())
        let id = timeline.insertOverlay(try yellowPhoto(), at: 0)
        timeline.resetTransform(ofClip: id)
        let overlayTrack = timeline.overlays[0].trackID

        // Overlay tracks start under text: the blue box shows.
        var output = try await CompositionBuilder.build(timeline, store: store)
        var center = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(center.b > 200, "Text above the overlay, got \(center)")

        timeline.moveTrack(overlayTrack, up: true)
        output = try await CompositionBuilder.build(timeline, store: store)
        center = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(center.r > 230 && center.b < 30, "Overlay above the text, got \(center)")
    }

    @Test func overlayVideosGetTheirOwnTracksAndInstructionsStillTile() async throws {
        var timeline = Timeline(clips: [try videoClip(), try videoClip()])
        timeline.insertOverlay(try videoClip(), at: 0.5)
        timeline.insertOverlay(try videoClip(), at: 1)
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(output.composition.tracks(withMediaType: .video).count == 3, "Main plus two overlapping overlays")

        let instructions = output.videoComposition.instructions.compactMap { $0 as? ClipInstruction }
        #expect(instructions.first?.timeRange.start == .zero)
        for (a, b) in zip(instructions, instructions.dropFirst()) {
            #expect(a.timeRange.end == b.timeRange.start)
        }
        #expect(instructions.last?.timeRange.end == output.composition.duration)
        let atOne = instructions.first { $0.timeRange.containsTime(CompositionBuilder.time(1.2)) }
        #expect(atOne?.overlays.count == 2)
        #expect(atOne?.requiredSourceTrackIDs?.count == 3)
    }

    @Test func overlayCutsKeepTheWholeTransition() async throws {
        var photo = try yellowPhoto()
        photo.transition = ClipTransition(kind: .crossfade, duration: 1)
        var timeline = Timeline(clips: [photo, .video(mediaFile: "gone.mov", duration: 3)])
        // Starts in the middle of the 2 s...3 s transition.
        timeline.insertOverlay(try yellowPhoto(), at: 2.5)
        let output = try await CompositionBuilder.build(timeline, store: store)
        let pieces = output.videoComposition.instructions.compactMap { $0 as? ClipInstruction }.filter { $0.transition != nil }
        #expect(pieces.count == 2)
        #expect(pieces.allSatisfy { abs($0.transitionRange.start.seconds - 2) < 0.01 && abs($0.transitionRange.duration.seconds - 1) < 0.01 })
    }

    @Test func gapsInTheMainTrackAreBlack() async throws {
        var timeline = Timeline(clips: [try yellowPhoto(), try yellowPhoto()])
        timeline.setMagnetic(false)
        timeline.slideClip(timeline.clips[1].id, toStart: 5)
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(abs(output.composition.duration.seconds - 8) < 0.02)
        let gap = TestMedia.centerColor(of: try await frame(of: output, at: 4))
        let after = TestMedia.centerColor(of: try await frame(of: output, at: 6))
        #expect(gap.r < 20, "Black in the gap, got \(gap)")
        #expect(after.r > 230, "The second photo after it, got \(after)")
    }

    @Test func textOnASecondTrackIsDrawn() async throws {
        var timeline = Timeline(clips: [try yellowPhoto()])
        timeline.upsertText(TextItem(text: "x", timelineStart: 0, duration: 3))
        timeline.upsertText(blueBox())
        #expect(timeline.textItems[1].trackID != Track.firstText.id)
        let output = try await CompositionBuilder.build(timeline, store: store)
        let center = TestMedia.centerColor(of: try await frame(of: output, at: 1))
        #expect(center.b > 200, "Got \(center)")
    }
}
