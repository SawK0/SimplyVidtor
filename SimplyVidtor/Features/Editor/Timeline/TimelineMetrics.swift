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

    enum Row: Equatable {
        case main
        case track(Track)
    }

    /// Rows in display order: the main track, visual tracks (drawing order), then audio.
    static func displayTracks(of timeline: Timeline) -> [Track] {
        timeline.visualTracks + timeline.audioTracks
    }

    /// The row under `y` in the tracks' coordinates; the gap between rows
    /// counts toward the nearer one.
    static func row(atY y: CGFloat, in timeline: Timeline) -> Row? {
        let gap = Theme.Spacing.xs
        var top = Theme.Size.rulerHeight + gap
        var rows: [(Row, CGFloat)] = [(.main, Theme.Size.timelineClipHeight)]
        rows += displayTracks(of: timeline).map { (.track($0), height(of: $0.kind)) }
        for (row, height) in rows {
            if y >= top - gap / 2, y < top + height + gap / 2 { return row }
            top += height + gap
        }
        return nil
    }

    /// Whether a touch at `point` (tracks' coordinates) lands on something it
    /// drags: a selected overlay, text or audio item, or a selected main clip's
    /// trim handles. The timeline mustn't start scrolling there, or a fast drag
    /// scrolls before the item's drag gesture begins.
    static func grabsSelection(at point: CGPoint, in timeline: Timeline, metrics: TimelineMetrics, selected: Set<UUID>) -> Bool {
        guard !selected.isEmpty, let row = row(atY: point.y, in: timeline) else { return false }
        let slop = Theme.Spacing.xs
        func covers(_ range: Range<Double>) -> Bool {
            point.x >= metrics.offset(for: range.lowerBound) - slop && point.x <= metrics.offset(for: range.upperBound) + slop
        }
        switch row {
        case .main:
            guard let index = timeline.clips.firstIndex(where: { selected.contains($0.id) }) else { return false }
            let range = timeline.timeRange(ofClipAt: index)
            let start = metrics.offset(for: range.lowerBound)
            let end = metrics.offset(for: range.upperBound) - Theme.Size.clipGap
            let handle = Theme.Size.trimHandleWidth + slop
            return (point.x >= start - slop && point.x <= start + handle) || (point.x >= end - handle && point.x <= end + slop)
        case .track(let track):
            switch track.kind {
            case .video:
                return timeline.overlays.contains { $0.trackID == track.id && selected.contains($0.id) && covers($0.timeRange) }
            case .text:
                return timeline.textItems.contains {
                    $0.trackID == track.id && selected.contains($0.id) && covers($0.timelineStart..<$0.timelineEnd)
                }
            case .audio:
                return timeline.audioItems.contains {
                    $0.trackID == track.id && selected.contains($0.id) && covers($0.timelineStart..<$0.timelineEnd)
                }
            }
        }
    }

    /// The editor shows the default rows plus up to two more; past that the timeline scrolls.
    static func visibleHeight(for timeline: Timeline) -> CGFloat {
        min(contentHeight(for: timeline), contentHeight(for: Timeline()) + 2 * Theme.Size.overlayTrackHeight)
    }
}
