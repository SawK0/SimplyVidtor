import Foundation

nonisolated enum MediaKind: String, Codable, Sendable {
    case video, photo
}

/// A span of one media file placed on the video track. Times are in seconds.
nonisolated struct Clip: Codable, Identifiable, Hashable, Sendable {
    static let speedRange: ClosedRange<Double> = 0.1...10
    /// AVAudioMix can't amplify, so full volume is the original level.
    static let volumeRange: ClosedRange<Double> = 0...1
    /// Shortest a clip may become on the timeline.
    static let minimumDuration: Double = 0.1
    static let defaultPhotoDuration: Double = 3

    var id: UUID
    /// File name inside the app's media folder.
    var mediaFile: String
    var kind: MediaKind
    /// Length of the source file; `nil` for photos, which can be any length.
    var mediaDuration: Double?
    var sourceStart: Double
    var sourceDuration: Double
    var speed: Double
    /// Keeps voices natural when the speed changes; off gives the chipmunk effect.
    var preservesPitch: Bool
    var volume: Double
    /// Silences the clip without losing its volume setting.
    var isMuted: Bool
    var filter: ClipFilter?
    var adjustments: ClipAdjustments
    /// Clockwise quarter turns, 0...3.
    var rotation: Int
    var crop: CropRect?
    /// Into the next clip; ignored on the last one.
    var transition: ClipTransition?
    var transform: ClipTransform

    init(
        id: UUID = UUID(),
        mediaFile: String,
        kind: MediaKind,
        mediaDuration: Double?,
        sourceStart: Double = 0,
        sourceDuration: Double,
        speed: Double = 1,
        preservesPitch: Bool = true,
        volume: Double = 1,
        isMuted: Bool = false,
        filter: ClipFilter? = nil,
        adjustments: ClipAdjustments = ClipAdjustments(),
        rotation: Int = 0,
        crop: CropRect? = nil,
        transition: ClipTransition? = nil,
        transform: ClipTransform = ClipTransform()
    ) {
        self.id = id
        self.mediaFile = mediaFile
        self.kind = kind
        self.mediaDuration = mediaDuration
        self.sourceStart = sourceStart
        self.sourceDuration = sourceDuration
        self.speed = speed
        self.preservesPitch = preservesPitch
        self.volume = volume
        self.isMuted = isMuted
        self.filter = filter
        self.adjustments = adjustments
        self.rotation = rotation
        self.crop = crop
        self.transition = transition
        self.transform = transform
    }

    static func video(mediaFile: String, duration: Double) -> Clip {
        Clip(mediaFile: mediaFile, kind: .video, mediaDuration: duration, sourceDuration: duration)
    }

    static func photo(mediaFile: String) -> Clip {
        Clip(mediaFile: mediaFile, kind: .photo, mediaDuration: nil, sourceDuration: defaultPhotoDuration)
    }

    /// Length on the timeline.
    var duration: Double { sourceDuration / speed }
    var sourceEnd: Double { sourceStart + sourceDuration }
    /// The level actually played.
    var effectiveVolume: Double { isMuted ? 0 : volume }
}

nonisolated extension Clip {
    /// Fields added after the first release are decoded leniently.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            mediaFile: try c.decode(String.self, forKey: .mediaFile),
            kind: try c.decode(MediaKind.self, forKey: .kind),
            mediaDuration: try c.decodeIfPresent(Double.self, forKey: .mediaDuration),
            sourceStart: try c.decode(Double.self, forKey: .sourceStart),
            sourceDuration: try c.decode(Double.self, forKey: .sourceDuration),
            speed: try c.decode(Double.self, forKey: .speed),
            preservesPitch: try c.decodeIfPresent(Bool.self, forKey: .preservesPitch) ?? true,
            volume: try c.decode(Double.self, forKey: .volume),
            isMuted: try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false,
            filter: try c.decodeIfPresent(ClipFilter.self, forKey: .filter),
            adjustments: try c.decodeIfPresent(ClipAdjustments.self, forKey: .adjustments) ?? ClipAdjustments(),
            rotation: try c.decodeIfPresent(Int.self, forKey: .rotation) ?? 0,
            crop: try c.decodeIfPresent(CropRect.self, forKey: .crop),
            transition: try c.decodeIfPresent(ClipTransition.self, forKey: .transition),
            transform: try c.decodeIfPresent(ClipTransform.self, forKey: .transform) ?? ClipTransform()
        )
    }
}

/// How a clip's picture is drawn, apart from timing.
nonisolated struct ClipLook: Hashable, Sendable {
    var filter: ClipFilter?
    var adjustments = ClipAdjustments()
    var rotation = 0
    var crop: CropRect?
    var transform = ClipTransform()
}

nonisolated extension Clip {
    var look: ClipLook {
        ClipLook(filter: filter, adjustments: adjustments, rotation: rotation, crop: crop, transform: transform)
    }
}
