import CoreGraphics
import SwiftUI

/// Maps between timeline seconds and points. The playhead is fixed at the
/// centre, so the scroll offset in points equals `time * pointsPerSecond`.
nonisolated struct TimelineMetrics: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 15...400
    static let defaultPointsPerSecond: CGFloat = 60
    /// Ruler ticks are at least this far apart.
    static let minimumTickSpacing: CGFloat = 64
    private static let tickIntervals: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]

    var pointsPerSecond: CGFloat = defaultPointsPerSecond

    func width(of seconds: Double) -> CGFloat {
        CGFloat(seconds) * pointsPerSecond
    }

    func offset(for time: Double) -> CGFloat {
        width(of: time)
    }

    func time(forOffset offset: CGFloat) -> Double {
        Double(offset / pointsPerSecond)
    }

    /// Smallest interval that keeps labels from crowding.
    var tickInterval: Double {
        Self.tickIntervals.first { width(of: $0) >= Self.minimumTickSpacing } ?? Self.tickIntervals.last!
    }

    func zoomed(by scale: CGFloat) -> TimelineMetrics {
        let pps = min(max(pointsPerSecond * scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        return TimelineMetrics(pointsPerSecond: pps)
    }
}

/// Row heights for the timeline's tracks.
enum TimelineLayout {
    static func height(of kind: TrackKind) -> CGFloat {
        switch kind {
        case .video: Theme.Size.overlayTrackHeight
        case .text: Theme.Size.textTrackHeight
        case .audio: Theme.Size.audioTrackHeight
        }
    }

    /// Ruler, main track and every other track, with the gaps between them.
    static func contentHeight(for timeline: Timeline) -> CGFloat {
        let rows = timeline.tracks.map { height(of: $0.kind) }
        return Theme.Size.rulerHeight + Theme.Size.timelineClipHeight + rows.reduce(0, +)
            + CGFloat(rows.count + 1) * Theme.Spacing.xs
    }

    /// The editor shows the default rows plus up to two more; past that the timeline scrolls.
    static func visibleHeight(for timeline: Timeline) -> CGFloat {
        min(contentHeight(for: timeline), contentHeight(for: Timeline()) + 2 * Theme.Size.overlayTrackHeight)
    }
}
