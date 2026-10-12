import Foundation

nonisolated enum MediaKind: String, Codable, Sendable {
    case video, photo
}

/// A span of one media file placed on the video track. Times are in seconds.
nonisolated struct Clip: Codable, Identifiable, Hashable, Sendable {
    static let speedRange: ClosedRange<Double> = 0.1...10
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

    init(
        id: UUID = UUID(),
        mediaFile: String,
        kind: MediaKind,
        mediaDuration: Double?,
        sourceStart: Double = 0,
        sourceDuration: Double,
        speed: Double = 1,
        preservesPitch: Bool = true,
        volume: Double = 1
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
}

extension Clip {
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
            volume: try c.decode(Double.self, forKey: .volume)
        )
    }
}
