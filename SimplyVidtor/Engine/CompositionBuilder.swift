import AVFoundation

/// Turns a `Timeline` into a composition and audio mix that `AVPlayer` and
/// the exporter can use. Photos and missing files are filled with a stretched
/// black clip: AVFoundation drops trailing empty ranges, which would cut the end off.
nonisolated enum CompositionBuilder {
    static let timescale: CMTimeScale = 600

    struct Output: @unchecked Sendable {
        let composition: AVComposition
        let audioMix: AVAudioMix
    }

    @concurrent
    static func build(_ timeline: Timeline, store: MediaStore) async throws -> Output {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let clipAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.featureUnsupported) }

        let clipAudio = AVMutableAudioMixInputParameters(track: clipAudioTrack)
        let blank = try await loadTracks(of: blankURL)
        var renderSize: CGSize?

        for (index, clip) in timeline.clips.enumerated() {
            let start = time(timeline.startTime(ofClipAt: index))
            let range = CMTimeRange(start: start, duration: time(clip.duration))
            guard clip.kind == .video,
                  let source = try await loadTracks(of: store.url(for: clip.mediaFile)),
                  let sourceVideo = source.video
            else {
                try insertBlank(blank, into: videoTrack, range: range)
                clipAudioTrack.insertEmptyTimeRange(range)
                continue
            }

            let sourceRange = CMTimeRange(start: time(clip.sourceStart), duration: time(clip.sourceDuration))
            try videoTrack.insertTimeRange(sourceRange, of: sourceVideo, at: start)
            if renderSize == nil {
                videoTrack.preferredTransform = source.transform
                renderSize = try await sourceVideo.load(.naturalSize)
            }
            if let audio = source.audio {
                try clipAudioTrack.insertTimeRange(sourceRange, of: audio, at: start)
            } else {
                clipAudioTrack.insertEmptyTimeRange(CMTimeRange(start: start, duration: sourceRange.duration))
            }
            if clip.speed != 1 {
                let inserted = CMTimeRange(start: start, duration: sourceRange.duration)
                videoTrack.scaleTimeRange(inserted, toDuration: range.duration)
                clipAudioTrack.scaleTimeRange(inserted, toDuration: range.duration)
            }
            clipAudio.setVolume(Float(clip.volume), at: start)
        }

        if let renderSize { composition.naturalSize = renderSize }

        var mixParameters = [clipAudio]
        for item in timeline.audioItems {
            guard let source = try await loadTracks(of: store.url(for: item.mediaFile)),
                  let audio = source.audio,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let sourceRange = CMTimeRange(start: time(item.sourceStart), duration: time(item.sourceDuration))
            try track.insertTimeRange(sourceRange, of: audio, at: time(item.timelineStart))
            mixParameters.append(volumeParameters(for: item, track: track))
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters
        return Output(composition: composition, audioMix: audioMix)
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
