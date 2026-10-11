import Foundation

/// A span of an audio file on the audio track. Times are in seconds.
nonisolated struct AudioItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var mediaFile: String
    var mediaDuration: Double
    var timelineStart: Double
    var sourceStart: Double
    var sourceDuration: Double
    var volume: Double
    var fadeIn: Double
    var fadeOut: Double

    init(
        id: UUID = UUID(),
        mediaFile: String,
        mediaDuration: Double,
        timelineStart: Double = 0,
        sourceStart: Double = 0,
        sourceDuration: Double? = nil,
        volume: Double = 1,
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) {
        self.id = id
        self.mediaFile = mediaFile
        self.mediaDuration = mediaDuration
        self.timelineStart = timelineStart
        self.sourceStart = sourceStart
        self.sourceDuration = sourceDuration ?? mediaDuration
        self.volume = volume
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    var timelineEnd: Double { timelineStart + sourceDuration }
}
