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
    var sourceEnd: Double { sourceStart + sourceDuration }

    static let minimumDuration: Double = 0.1
    static let volumeRange: ClosedRange<Double> = 0...1
    /// Each fade is at most half the item, so the ramps never overlap.
    var maximumFade: Double { sourceDuration / 2 }

    /// Same span of audio, starting at `start` on the timeline (not before 0).
    func moved(toStart start: Double) -> AudioItem {
        var item = self
        item.timelineStart = max(start, 0)
        return item
    }

    /// Moves the in-point by `delta` seconds, keeping the out-point (on the
    /// timeline and in the file) fixed.
    func trimmingStart(by delta: Double) -> AudioItem {
        let earliest = max(-sourceStart, -timelineStart)
        let latest = sourceDuration - Self.minimumDuration
        let delta = min(max(delta, earliest), latest)
        var item = self
        item.sourceStart += delta
        item.timelineStart += delta
        item.sourceDuration -= delta
        return item.clampingFades()
    }

    /// Moves the out-point by `delta` seconds, up to the end of the file.
    func trimmingEnd(by delta: Double) -> AudioItem {
        var item = self
        item.sourceDuration = min(max(sourceDuration + delta, Self.minimumDuration), mediaDuration - sourceStart)
        return item.clampingFades()
    }

    /// Volume and fades within their ranges.
    func clampingFades() -> AudioItem {
        var item = self
        item.volume = min(max(volume, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
        item.fadeIn = min(max(fadeIn, 0), item.maximumFade)
        item.fadeOut = min(max(fadeOut, 0), item.maximumFade)
        return item
    }
}
