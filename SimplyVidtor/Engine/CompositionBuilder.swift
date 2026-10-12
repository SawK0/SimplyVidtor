import AVFoundation

/// Turns a `Timeline` into the composition, audio mix and video composition
/// that `AVPlayer` and the exporter use. Photos and missing files are filled with
/// a stretched black clip (AVFoundation drops trailing empty ranges) and drawn by
/// `VideoCompositor`.
nonisolated enum CompositionBuilder {
    static let timescale: CMTimeScale = 600
    static let frameRate: Int32 = 30
    /// Used when the timeline has no video to take a size from.
    static let defaultRenderSize = CGSize(width: 1080, height: 1920)

    struct Output: @unchecked Sendable {
        let composition: AVComposition
        let audioMix: AVAudioMix
        let videoComposition: AVVideoComposition
    }

    @concurrent
    static func build(_ timeline: Timeline, store: MediaStore) async throws -> Output {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let clipAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.featureUnsupported) }

        // Pitch is set per track, so clips that don't keep pitch get a second track.
        let varispeedTrack = timeline.clips.contains { $0.kind == .video && !$0.preservesPitch }
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil
        let clipAudio = AVMutableAudioMixInputParameters(track: clipAudioTrack)
        clipAudio.audioTimePitchAlgorithm = .spectral
        let varispeedAudio = varispeedTrack.map { AVMutableAudioMixInputParameters(track: $0) }
        varispeedAudio?.audioTimePitchAlgorithm = .varispeed
        let clipAudioTracks = [clipAudioTrack] + (varispeedTrack.map { [$0] } ?? [])
        let blank = try await loadTracks(of: blankURL)
        var renderSize: CGSize?
        var instructions: [ClipInstruction] = []

        // Boundaries are computed once so track segments and instructions meet exactly.
        let boundaries = (0...timeline.clips.count).map { time(timeline.startTime(ofClipAt: $0)) }

        for (index, clip) in timeline.clips.enumerated() {
            let range = CMTimeRange(start: boundaries[index], end: boundaries[index + 1])
            guard clip.kind == .video,
                  let source = try await loadTracks(of: store.url(for: clip.mediaFile)),
                  let sourceVideo = source.video
            else {
                try insertBlank(blank, into: videoTrack, range: range)
                clipAudioTracks.forEach { $0.insertEmptyTimeRange(range) }
                let url = store.url(for: clip.mediaFile)
                let isPhoto = clip.kind == .photo && FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
                instructions.append(ClipInstruction(
                    timeRange: range,
                    content: isPhoto ? .photo(url) : .blank,
                    filter: clip.filter,
                    adjustments: clip.adjustments
                ))
                continue
            }

            let sourceRange = CMTimeRange(start: time(clip.sourceStart), duration: time(clip.sourceDuration))
            let inserted = CMTimeRange(start: range.start, duration: sourceRange.duration)
            let audioTrack = clip.preservesPitch ? clipAudioTrack : varispeedTrack ?? clipAudioTrack
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: range.start)
            if let audio = source.audio {
                try audioTrack.insertTimeRange(sourceRange, of: audio, at: range.start)
            } else {
                audioTrack.insertEmptyTimeRange(inserted)
            }
            if inserted.duration != range.duration {
                videoTrack.scaleTimeRange(inserted, toDuration: range.duration)
                audioTrack.scaleTimeRange(inserted, toDuration: range.duration)
            }
            for track in clipAudioTracks where track !== audioTrack {
                track.insertEmptyTimeRange(range)
            }
            let parameters = audioTrack === clipAudioTrack ? clipAudio : varispeedAudio ?? clipAudio
            parameters.setVolume(Float(clip.effectiveVolume), at: range.start)

            let orientation = CGImagePropertyOrientation(source.transform)
            if renderSize == nil {
                let size = try await sourceVideo.load(.naturalSize)
                renderSize = orientation == .left || orientation == .right ? CGSize(width: size.height, height: size.width) : size
            }
            instructions.append(ClipInstruction(
                timeRange: range,
                content: .video(trackID: videoTrack.trackID, orientation: orientation),
                filter: clip.filter,
                adjustments: clip.adjustments
            ))
        }

        var mixParameters = [clipAudio] + (varispeedAudio.map { [$0] } ?? [])
        for item in timeline.audioItems {
            guard let source = try await loadTracks(of: store.url(for: item.mediaFile)),
                  let audio = source.audio,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let sourceRange = CMTimeRange(start: time(item.sourceStart), duration: time(item.sourceDuration))
            try track.insertTimeRange(sourceRange, of: audio, at: time(item.timelineStart))
            mixParameters.append(volumeParameters(for: item, track: track))
        }

        // Instructions must cover the whole composition, including audio past the last clip.
        let videoEnd = boundaries.last ?? .zero
        if composition.duration > videoEnd {
            instructions.append(ClipInstruction(timeRange: CMTimeRange(start: videoEnd, end: composition.duration), content: .blank))
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)
        videoComposition.renderSize = renderSize ?? defaultRenderSize

        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition)
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    private static let blankURL = Bundle.main.url(forResource: "blank", withExtension: "mov")!

    private static func insertBlank(_ blank: SourceTracks?, into track: AVMutableCompositionTrack, range: CMTimeRange) throws {
        guard let blank, let video = blank.video else {
            track.insertEmptyTimeRange(range)
            return
        }
        let one = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        try track.insertTimeRange(one, of: video, at: range.start)
        track.scaleTimeRange(CMTimeRange(start: range.start, duration: one.duration), toDuration: range.duration)
    }

    private struct SourceTracks {
        /// Held because tracks don't retain their asset, and inserting from an orphaned track fails.
        let asset: AVURLAsset
        let video: AVAssetTrack?
        let audio: AVAssetTrack?
        let transform: CGAffineTransform
    }

    /// `nil` when the file is missing.
    private static func loadTracks(of url: URL) async throws -> SourceTracks? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let transform = try await video?.load(.preferredTransform) ?? .identity
        return SourceTracks(asset: asset, video: video, audio: audio, transform: transform)
    }

    private static func volumeParameters(for item: AudioItem, track: AVCompositionTrack) -> AVMutableAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        let volume = Float(item.volume)
        let start = item.timelineStart
        let end = item.timelineEnd
        if item.fadeIn > 0 {
            parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                                     timeRange: CMTimeRange(start: time(start), duration: time(item.fadeIn)))
        } else {
            parameters.setVolume(volume, at: time(start))
        }
        if item.fadeOut > 0 {
            parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                                     timeRange: CMTimeRange(start: time(end - item.fadeOut), duration: time(item.fadeOut)))
        }
        return parameters
    }
}
