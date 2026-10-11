import AVFoundation
import Foundation
import Testing
@testable import SimplyVidtor

struct CompositionBuilderTests {
    let store = MediaStore.temporary()

    private func sampleClip() throws -> Clip {
        .video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
    }

    private func toneItem() throws -> AudioItem {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: url)
        return AudioItem(mediaFile: try store.moveIn(url), mediaDuration: 2)
    }

    private func seconds(_ composition: AVComposition) -> Double {
        composition.duration.seconds
    }

    @Test func durationMatchesTimelineWithSpeedAndPhotos() async throws {
        var fast = try sampleClip()
        fast.speed = 2
        let timeline = Timeline(clips: [try sampleClip(), fast, .photo(mediaFile: "missing.heic")])

        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(abs(seconds(output.composition) - timeline.duration) < 0.02)
        #expect(abs(timeline.duration - 6) < 1e-9)
    }

    @Test func trimmedClipUsesSourceRange() async throws {
        var clip = try sampleClip()
        clip.sourceStart = 0.5
        clip.sourceDuration = 1
        let output = try await CompositionBuilder.build(Timeline(clips: [clip]), store: store)
        #expect(abs(seconds(output.composition) - 1) < 0.02)
    }

    @Test func missingFileKeepsTiming() async throws {
        let timeline = Timeline(clips: [.video(mediaFile: "gone.mov", duration: 5), try sampleClip()])
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(abs(seconds(output.composition) - 7) < 0.02)
    }

    @Test func audioItemsGetTheirOwnTrackAndMixParameters() async throws {
        var item = try toneItem()
        item.timelineStart = 1
        item.fadeIn = 0.5
        let timeline = Timeline(clips: [try sampleClip()], audioItems: [item])

        let output = try await CompositionBuilder.build(timeline, store: store)
        let audioTracks = output.composition.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 2)
        #expect(output.audioMix.inputParameters.count == 2)
        #expect(abs(seconds(output.composition) - 3) < 0.02, "Audio past the last clip extends the composition")
    }

    @Test func missingAudioFileIsSkipped() async throws {
        let timeline = Timeline(
            clips: [try sampleClip()],
            audioItems: [AudioItem(mediaFile: "gone.m4a", mediaDuration: 4)]
        )
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(output.composition.tracks(withMediaType: .audio).count == 1)
    }

    @Test func emptyTimelineBuilds() async throws {
        let output = try await CompositionBuilder.build(Timeline(), store: store)
        #expect(output.composition.duration == .zero)
    }
}
