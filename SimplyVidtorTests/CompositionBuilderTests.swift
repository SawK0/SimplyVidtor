import AVFoundation
import Foundation
import Testing
@testable import SimplyVidtor

struct CompositionBuilderTests {
    let store = MediaStore.temporary()

    private func sampleClip() throws -> Clip {
        .video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
    }

    private func soundClip() async throws -> Clip {
        .video(mediaFile: try store.moveIn(try await TestMedia.soundVideoCopy()), duration: 2)
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
        let timeline = Timeline(clips: [try await soundClip()], audioItems: [item])

        let output = try await CompositionBuilder.build(timeline, store: store)
        let audioTracks = output.composition.tracks(withMediaType: .audio)
        #expect(audioTracks.count == 2)
        #expect(output.audioMix.inputParameters.count == 2)
        #expect(abs(seconds(output.composition) - 2) < 0.02, "Audio is cut at the video's end")
    }

    @Test func missingAudioFileIsSkipped() async throws {
        let timeline = Timeline(
            clips: [try await soundClip()],
            audioItems: [AudioItem(mediaFile: "gone.m4a", mediaDuration: 4)]
        )
        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(output.composition.tracks(withMediaType: .audio).count == 1)
    }

    @Test func emptyTimelineBuilds() async throws {
        let output = try await CompositionBuilder.build(Timeline(), store: store)
        #expect(output.composition.duration == .zero)
    }

    @Test func clipsThatDontKeepPitchUseAVarispeedTrack() async throws {
        var chipmunk = try await soundClip()
        chipmunk.speed = 2
        chipmunk.preservesPitch = false
        let timeline = Timeline(clips: [try await soundClip(), chipmunk])

        let output = try await CompositionBuilder.build(timeline, store: store)
        #expect(output.composition.tracks(withMediaType: .audio).count == 2)
        let algorithms = output.audioMix.inputParameters.map(\.audioTimePitchAlgorithm)
        #expect(algorithms == [.spectral, .varispeed])
        #expect(abs(seconds(output.composition) - 3) < 0.02)
    }

    @Test func pitchKeepingClipsShareOneTrack() async throws {
        let output = try await CompositionBuilder.build(Timeline(clips: [try await soundClip(), try await soundClip()]), store: store)
        #expect(output.composition.tracks(withMediaType: .audio).count == 1)
        #expect(output.audioMix.inputParameters.first?.audioTimePitchAlgorithm == .spectral)
    }

    @Test func mutedClipPlaysSilently() async throws {
        var muted = try await soundClip()
        muted.volume = 0.8
        muted.isMuted = true
        let output = try await CompositionBuilder.build(Timeline(clips: [try await soundClip(), muted]), store: store)

        let parameters = try #require(output.audioMix.inputParameters.first)
        #expect(volume(of: parameters, at: 1) == 1)
        #expect(volume(of: parameters, at: 3) == 0)
    }

    private func volume(of parameters: AVAudioMixInputParameters, at seconds: Double) -> Float {
        var start: Float = -1
        var end: Float = -1
        var range = CMTimeRange.zero
        _ = parameters.getVolumeRamp(for: CompositionBuilder.time(seconds), startVolume: &start, endVolume: &end, timeRange: &range)
        return start
    }

    @Test func silentClipsLeaveNoEmptyAudioTracks() async throws {
        // Export rejects audio tracks that hold only empty ranges.
        let output = try await CompositionBuilder.build(Timeline(clips: [try sampleClip(), .photo(mediaFile: "p.heic")]), store: store)
        #expect(output.composition.tracks(withMediaType: .audio).isEmpty)
        #expect(output.audioMix.inputParameters.isEmpty)
    }

    @Test func audioStartingAfterTheVideoIsLeftOut() async throws {
        var item = try toneItem()
        item.timelineStart = 5
        let output = try await CompositionBuilder.build(Timeline(clips: [try sampleClip()], audioItems: [item]), store: store)
        #expect(output.composition.tracks(withMediaType: .audio).isEmpty)
        #expect(abs(seconds(output.composition) - 2) < 0.02)
    }
}
