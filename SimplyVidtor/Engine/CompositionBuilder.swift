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
        /// Whether any source clip has HDR video.
        let containsHDR: Bool
    }

    /// Text is drawn from `overlays` (made from the timeline when not given),
    /// which the editor can update without a rebuild.
    @concurrent
    static func build(_ timeline: Timeline, store: MediaStore, overlays: OverlayStore? = nil) async throws -> Output {
        let overlays = overlays ?? OverlayStore()
        overlays.textItems = timeline.textItems
        let composition = AVMutableComposition()
        let tracks = try Tracks(composition: composition)
        let blank = try await loadTracks(of: blankURL)
        let clips = timeline.clips
        var firstVideoSize: CGSize?
        var containsHDR = false
        var layers: [ClipInstruction.Layer] = []

        // Clip ranges are computed once so track segments and instructions meet exactly.
        // A clip with a transition runs past the next clip's start by the overlap.
        let starts = (0...clips.count).map { time(timeline.startTime(ofClipAt: $0)) }
        let ends = clips.indices.map { index in
            timeline.overlap(afterClipAt: index) > 0
                ? time(timeline.startTime(ofClipAt: index) + clips[index].duration)
                : starts[index + 1]
        }

        // Overlapping clips alternate between two lanes.
        var lane = 0
        for (index, clip) in clips.enumerated() {
            if index > 0, timeline.overlap(afterClipAt: index - 1) > 0 { lane = 1 - lane }
            let range = CMTimeRange(start: starts[index], end: ends[index])
            let videoLane = try tracks.video(lane)

            guard clip.kind == .video,
                  let source = try await loadTracks(of: store.url(for: clip.mediaFile)),
                  let sourceVideo = source.video
            else {
                videoLane.pad(to: range.start)
                try insertBlank(blank, into: videoLane.track, range: range)
                videoLane.end = range.end
                let url = store.url(for: clip.mediaFile)
                let isPhoto = clip.kind == .photo && FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
                layers.append(ClipInstruction.Layer(content: isPhoto ? .photo(url) : .blank, clip: clip))
                continue
            }

            let sourceRange = CMTimeRange(start: time(clip.sourceStart), duration: time(clip.sourceDuration))
            let inserted = CMTimeRange(start: range.start, duration: sourceRange.duration)
            let audioLane = try tracks.audio(lane, varispeed: !clip.preservesPitch)
            videoLane.pad(to: range.start)
            audioLane.pad(to: range.start)
            try videoLane.track.insertTimeRange(sourceRange, of: sourceVideo, at: range.start)
            if let audio = source.audio {
                try audioLane.track.insertTimeRange(sourceRange, of: audio, at: range.start)
            } else {
                audioLane.track.insertEmptyTimeRange(inserted)
            }
            if inserted.duration != range.duration {
                videoLane.track.scaleTimeRange(inserted, toDuration: range.duration)
                audioLane.track.scaleTimeRange(inserted, toDuration: range.duration)
            }
            videoLane.end = range.end
            audioLane.end = range.end

            // Audio cross-fades across transitions.
            let volume = Float(clip.effectiveVolume)
            if index > 0, timeline.overlap(afterClipAt: index - 1) > 0 {
                audioLane.parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                                                   timeRange: CMTimeRange(start: range.start, end: ends[index - 1]))
            } else {
                audioLane.parameters.setVolume(volume, at: range.start)
            }
            if timeline.overlap(afterClipAt: index) > 0 {
                audioLane.parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                                                   timeRange: CMTimeRange(start: starts[index + 1], end: range.end))
            }

            if !containsHDR, try await sourceVideo.load(.mediaCharacteristics).contains(.containsHDRVideo) {
                containsHDR = true
            }
            let orientation = CGImagePropertyOrientation(source.transform)
            if firstVideoSize == nil {
                let size = try await sourceVideo.load(.naturalSize)
                let oriented = orientation == .left || orientation == .right ? CGSize(width: size.height, height: size.width) : size
                firstVideoSize = FilterRenderer.framedSize(oriented, rotation: clip.rotation, crop: clip.crop)
            }
            layers.append(ClipInstruction.Layer(
                content: .video(trackID: videoLane.track.trackID, orientation: orientation),
                clip: clip
            ))
        }

        var mixParameters = tracks.mixParameters
        for item in timeline.audioItems {
            guard let source = try await loadTracks(of: store.url(for: item.mediaFile)),
                  let audio = source.audio,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let sourceRange = CMTimeRange(start: time(item.sourceStart), duration: time(item.sourceDuration))
            try track.insertTimeRange(sourceRange, of: audio, at: time(item.timelineStart))
            mixParameters.append(volumeParameters(for: item, track: track))
        }

        // Instructions tile the whole composition: each clip alone, then its
        // transition into the next, then blank under audio past the last clip.
        var instructions: [ClipInstruction] = []
        var cursor = CMTime.zero
        func add(until end: CMTime, _ layers: [ClipInstruction.Layer], transition: TransitionKind? = nil) {
            guard end > cursor else { return }
            instructions.append(ClipInstruction(
                timeRange: CMTimeRange(start: cursor, end: end), layers: layers, transition: transition, overlays: overlays
            ))
            cursor = end
        }
        for index in clips.indices {
            let transition = timeline.overlap(afterClipAt: index) > 0 ? clips[index].transition : nil
            add(until: transition == nil ? ends[index] : starts[index + 1], [layers[index]])
            if let transition {
                add(until: ends[index], [layers[index], layers[index + 1]], transition: transition.kind)
            }
        }
        add(until: composition.duration, [])

        // Export rejects tracks that hold only empty ranges (e.g. clips without sound).
        for track in composition.tracks(withMediaType: .audio) where track.segments.allSatisfy(\.isEmpty) {
            composition.removeTrack(track)
            mixParameters.removeAll { $0.trackID == track.trackID }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParameters

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = VideoCompositor.self
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)
        videoComposition.renderSize = renderSize(aspectRatio: timeline.aspectRatio, firstVideoSize: firstVideoSize)

        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition, containsHDR: containsHDR)
    }

    /// A composition track filled up to `end`.
    private final class Lane {
        let track: AVMutableCompositionTrack
        let parameters: AVMutableAudioMixInputParameters
        var end = CMTime.zero

        init(_ track: AVMutableCompositionTrack, pitch: AVAudioTimePitchAlgorithm = .spectral) {
            self.track = track
            parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTimePitchAlgorithm = pitch
        }

        /// Fills any gap before `time` with an empty range.
        func pad(to time: CMTime) {
            guard time > end else { return }
            track.insertEmptyTimeRange(CMTimeRange(start: end, end: time))
            end = time
        }
    }

    /// Clip tracks, created on first use: two lanes for overlapping clips, and
    /// varispeed audio for clips that don't keep pitch (pitch is set per track).
    private final class Tracks {
        let composition: AVMutableComposition
        private var videoLanes: [Int: Lane] = [:]
        private var audioLanes: [String: Lane] = [:]
        private var audioOrder: [Lane] = []

        init(composition: AVMutableComposition) throws {
            self.composition = composition
            _ = try video(0)
            _ = try audio(0, varispeed: false)
        }

        func video(_ lane: Int) throws -> Lane {
            if let existing = videoLanes[lane] { return existing }
            let new = Lane(try addTrack(.video))
            videoLanes[lane] = new
            return new
        }

        func audio(_ lane: Int, varispeed: Bool) throws -> Lane {
            let key = "\(lane)-\(varispeed)"
            if let existing = audioLanes[key] { return existing }
            let new = Lane(try addTrack(.audio), pitch: varispeed ? .varispeed : .spectral)
            audioLanes[key] = new
            audioOrder.append(new)
            return new
        }

        var mixParameters: [AVAudioMixInputParameters] { audioOrder.map(\.parameters) }

        private func addTrack(_ type: AVMediaType) throws -> AVMutableCompositionTrack {
            guard let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CocoaError(.featureUnsupported)
            }
            return track
        }
    }

    /// The first video's framed size, or a canvas of `aspectRatio` with the same
    /// long side. Sides are rounded to even pixels for the encoder.
    static func renderSize(aspectRatio: AspectRatio?, firstVideoSize: CGSize?) -> CGSize {
        let base = firstVideoSize ?? defaultRenderSize
        let size: CGSize
        if let aspectRatio {
            let long = max(base.width, base.height)
            size = aspectRatio.value < 1
                ? CGSize(width: long * aspectRatio.value, height: long)
                : CGSize(width: long, height: long / aspectRatio.value)
        } else {
            size = base
        }
        let even = { (side: CGFloat) in max(2, (side / 2).rounded() * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
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
