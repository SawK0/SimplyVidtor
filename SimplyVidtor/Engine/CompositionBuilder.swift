import AVFoundation

/// Turns a `Timeline` into the composition, audio mix and video composition
/// that `AVPlayer` and the exporter use. Photos and missing files are filled with
/// a stretched black clip (AVFoundation drops trailing empty ranges) and drawn by
/// `VideoCompositor`.
nonisolated enum CompositionBuilder {
    static let timescale: CMTimeScale = 600
    /// Used when the timeline has no video to take a size from.
    static let defaultRenderSize = CGSize(width: 1080, height: 1920)

    struct Output: @unchecked Sendable {
        let composition: AVComposition
        let audioMix: AVAudioMix
        let videoComposition: AVVideoComposition
        /// Whether any source clip has HDR video.
        let containsHDR: Bool
    }

    /// Text and clip looks are drawn from `live` (made from the timeline when
    /// not given), which the editor can update without a rebuild.
    @concurrent
    static func build(_ timeline: Timeline, store: MediaStore, live: LiveStore? = nil) async throws -> Output {
        let live = live ?? LiveStore()
        live.update(from: timeline)
        let composition = AVMutableComposition()
        let tracks = try Tracks(composition: composition)
        let blank = try await loadTracks(of: blankURL)
        let clips = timeline.clips
        var firstVideoSize: CGSize?
        var containsHDR = false
        var layers: [ClipInstruction.Layer] = []

        // Clip ranges are computed once so track segments and instructions meet exactly.
        // A clip with a transition runs past the next clip's start by the overlap;
        // one followed by a gap ends before it.
        let starts = (0...clips.count).map { time(timeline.startTime(ofClipAt: $0)) }
        let ends = clips.indices.map { index in
            timeline.overlap(afterClipAt: index) > 0 || timeline.gap(beforeClipAt: index + 1) > 0
                ? time(timeline.startTime(ofClipAt: index) + clips[index].duration)
                : starts[index + 1]
        }

        // Overlapping clips alternate between two lanes.
        var lane = 0
        for (index, clip) in clips.enumerated() {
            if index > 0, timeline.overlap(afterClipAt: index - 1) > 0 { lane = 1 - lane }
            let range = CMTimeRange(start: starts[index], end: ends[index])
            let videoLane = try tracks.video(lane)
            // Gaps (magnet off) need frames too, or players show the last one.
            if timeline.gap(beforeClipAt: index) > 0, range.start > videoLane.end {
                try insertBlank(blank, into: videoLane.track, range: CMTimeRange(start: videoLane.end, end: range.start))
                videoLane.end = range.start
            }

            guard clip.kind == .video,
                  let source = try await loadTracks(of: store.url(for: clip.mediaFile)),
                  let sourceVideo = source.video
            else {
                videoLane.pad(to: range.start)
                try insertBlank(blank, into: videoLane.track, range: range)
                videoLane.end = range.end
                let url = store.url(for: clip.mediaFile)
                let isPhoto = clip.kind == .photo && FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
                layers.append(ClipInstruction.Layer(content: isPhoto ? .photo(url) : .blank, clip: clip, start: range.start.seconds))
                continue
            }

            let audioLane = try tracks.audio(lane, varispeed: !clip.preservesPitch)
            try insert(clip, video: sourceVideo, audio: source.audio, range: range, videoLane: videoLane, audioLane: audioLane)

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
                clip: clip,
                start: range.start.seconds
            ))
        }

        // Overlay clips get composition tracks of their own, reused once free.
        var overlays: [(range: CMTimeRange, overlay: ClipInstruction.Overlay)] = []
        for overlay in timeline.overlays {
            let clip = overlay.clip
            let range = CMTimeRange(start: time(overlay.timelineStart), duration: time(clip.duration))
            let url = store.url(for: clip.mediaFile)
            let layer: ClipInstruction.Layer
            if clip.kind == .video, let source = try await loadTracks(of: url), let sourceVideo = source.video {
                let lane = tracks.freeOverlayLane(at: range.start)
                let videoLane = try tracks.video(lane)
                let audioLane = try tracks.audio(lane, varispeed: !clip.preservesPitch)
                try insert(clip, video: sourceVideo, audio: source.audio, range: range, videoLane: videoLane, audioLane: audioLane)
                audioLane.parameters.setVolume(Float(clip.effectiveVolume), at: range.start)
                if !containsHDR, try await sourceVideo.load(.mediaCharacteristics).contains(.containsHDRVideo) {
                    containsHDR = true
                }
                layer = ClipInstruction.Layer(
                    content: .video(trackID: videoLane.track.trackID, orientation: CGImagePropertyOrientation(source.transform)),
                    clip: clip, start: range.start.seconds
                )
            } else if clip.kind == .photo, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                layer = ClipInstruction.Layer(content: .photo(url), clip: clip, start: range.start.seconds)
            } else {
                continue
            }
            overlays.append((range, ClipInstruction.Overlay(trackID: overlay.trackID, layer: layer)))
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

        // Black under audio and text that run past the last clip.
        let main = try tracks.video(0)
        let end = time(timeline.duration)
        if end > main.end {
            try insertBlank(blank, into: main.track, range: CMTimeRange(start: main.end, end: end))
            main.end = end
        }

        // Instructions tile the whole composition: gaps, each clip alone, its
        // transition into the next, then black past the last clip.
        var segments: [(range: CMTimeRange, layers: [ClipInstruction.Layer], transition: TransitionKind?)] = []
        var cursor = CMTime.zero
        func add(until end: CMTime, _ layers: [ClipInstruction.Layer], transition: TransitionKind? = nil) {
            guard end > cursor else { return }
            segments.append((CMTimeRange(start: cursor, end: end), layers, transition))
            cursor = end
        }
        for index in clips.indices {
            add(until: starts[index], [])
            let transition = timeline.overlap(afterClipAt: index) > 0 ? clips[index].transition : nil
            add(until: transition == nil ? ends[index] : starts[index + 1], [layers[index]])
            if let transition {
                add(until: ends[index], [layers[index], layers[index + 1]], transition: transition.kind)
            }
        }
        add(until: composition.duration, [])

        // Overlays start and stop mid-segment, so segments are cut where they do.
        let cuts = Set(overlays.flatMap { [$0.range.start, $0.range.end] })
        var instructions: [ClipInstruction] = []
        for segment in segments {
            var start = segment.range.start
            let inside = cuts.filter { $0 > segment.range.start && $0 < segment.range.end }.sorted()
            for end in inside + [segment.range.end] {
                let active = overlays.filter { $0.range.start <= start && $0.range.end >= end }.map(\.overlay)
                instructions.append(ClipInstruction(
                    timeRange: CMTimeRange(start: start, end: end), layers: segment.layers, transition: segment.transition,
                    transitionRange: segment.range, overlays: active, live: live
                ))
                start = end
            }
        }

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
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(timeline.format.frameRate))
        videoComposition.renderSize = renderSize(format: timeline.format, firstVideoSize: firstVideoSize)

        return Output(composition: composition, audioMix: audioMix, videoComposition: videoComposition, containsHDR: containsHDR)
    }

    /// Inserts a video clip's picture and sound at `range`, stretched to its speed.
    private static func insert(_ clip: Clip, video: AVAssetTrack, audio: AVAssetTrack?, range: CMTimeRange,
                               videoLane: Lane, audioLane: Lane) throws {
        let sourceRange = CMTimeRange(start: time(clip.sourceStart), duration: time(clip.sourceDuration))
        let inserted = CMTimeRange(start: range.start, duration: sourceRange.duration)
        videoLane.pad(to: range.start)
        audioLane.pad(to: range.start)
        try videoLane.track.insertTimeRange(sourceRange, of: video, at: range.start)
        if let audio {
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

        /// Overlay lanes are numbered from here, clear of the main track's two.
        private static let firstOverlayLane = 1000

        /// The first overlay lane whose last clip ends by `start`.
        func freeOverlayLane(at start: CMTime) -> Int {
            var lane = Self.firstOverlayLane
            while let existing = videoLanes[lane], existing.end > start { lane += 1 }
            return lane
        }

        private func addTrack(_ type: AVMediaType) throws -> AVMutableCompositionTrack {
            guard let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CocoaError(.featureUnsupported)
            }
            return track
        }
    }

    /// Preview frames are capped here; export rescales to its own resolution.
    static let maxWorkingResolution = 1080

    /// The format's shape (or the first video's framed shape), scaled so the
    /// shorter side is the format's resolution, capped for previewing.
    /// Sides are rounded to even pixels for the encoder.
    static func renderSize(format: ProjectFormat, firstVideoSize: CGSize?) -> CGSize {
        let shape = format.aspectRatio.map { CGSize(width: $0.value, height: 1) } ?? firstVideoSize ?? defaultRenderSize
        let short = CGFloat(min(format.resolution, maxWorkingResolution))
        let scale = short / max(min(shape.width, shape.height), 0.0001)
        let even = { (side: CGFloat) in max(2, (side * scale / 2).rounded() * 2) }
        return CGSize(width: even(shape.width), height: even(shape.height))
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
