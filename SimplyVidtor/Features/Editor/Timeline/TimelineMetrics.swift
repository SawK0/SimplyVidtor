import CoreGraphics
import SwiftUI

/// Maps between timeline seconds and points, and scales row heights. The
/// playhead is fixed at the centre, so the scroll offset in points equals
/// `time * pointsPerSecond`.
nonisolated struct TimelineMetrics: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 15...400
    static let rowScaleRange: ClosedRange<CGFloat> = 0.6...2
    static let defaultPointsPerSecond: CGFloat = 60
    /// Ruler ticks are at least this far apart.
    static let minimumTickSpacing: CGFloat = 64
    private static let tickIntervals: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]

    var pointsPerSecond: CGFloat = defaultPointsPerSecond
    /// Row heights relative to the design's.
    var rowScale: CGFloat = 1

    func width(of seconds: Double) -> CGFloat {
        CGFloat(seconds) * pointsPerSecond
    }

    func offset(for time: Double) -> CGFloat {
        width(of: time)
    }

    func time(forOffset offset: CGFloat) -> Double {
        Double(offset / pointsPerSecond)
    }

    /// Dragged items snap to edges this close.
    static let snapDistance: CGFloat = 10

    var snapTolerance: Double { time(forOffset: Self.snapDistance) }

    /// Smallest interval that keeps labels from crowding.
    var tickInterval: Double {
        Self.tickIntervals.first { width(of: $0) >= Self.minimumTickSpacing } ?? Self.tickIntervals.last!
    }

    func zoomed(by scale: CGFloat) -> TimelineMetrics {
        var zoomed = self
        zoomed.pointsPerSecond = min(max(pointsPerSecond * scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        return zoomed
    }

    /// Taller (or shorter) rows.
    func rowsZoomed(by scale: CGFloat) -> TimelineMetrics {
        var zoomed = self
        zoomed.rowScale = min(max(rowScale * scale, Self.rowScaleRange.lowerBound), Self.rowScaleRange.upperBound)
        return zoomed
    }
}

/// Row heights for the timeline's tracks, scaled by `TimelineMetrics.rowScale`.
enum TimelineLayout {
    static func height(of kind: TrackKind, _ metrics: TimelineMetrics) -> CGFloat {
        let base = switch kind {
        case .video: Theme.Size.overlayTrackHeight
        case .text: Theme.Size.textTrackHeight
        case .audio: Theme.Size.audioTrackHeight
        }
        return base * metrics.rowScale
    }

    /// Ruler and every row, with the gaps between them.
    static func contentHeight(for timeline: Timeline, _ metrics: TimelineMetrics) -> CGFloat {
        let rows = rows(of: timeline)
        let heights = rows.map { $0.height(metrics) }.reduce(0, +)
        return Theme.Size.rulerHeight + heights + CGFloat(rows.count) * Theme.Spacing.xs
    }

    enum Row: Hashable {
        case main
        case track(Track)

        func height(_ metrics: TimelineMetrics) -> CGFloat {
            switch self {
            case .main: Theme.Size.timelineClipHeight * metrics.rowScale
            case .track(let track): TimelineLayout.height(of: track.kind, metrics)
            }
        }
    }

    /// Video and text tracks above the main track, the top one drawn on top;
    /// audio tracks below.
    static func rows(of timeline: Timeline) -> [Row] {
        timeline.visualTracks.reversed().map { .track($0) } + [.main] + timeline.audioTracks.map { .track($0) }
    }

    /// The row under `y` in the tracks' coordinates; the gap between rows
    /// counts toward the nearer one.
    static func row(atY y: CGFloat, in timeline: Timeline, _ metrics: TimelineMetrics) -> Row? {
        let gap = Theme.Spacing.xs
        var top = Theme.Size.rulerHeight + gap
        for row in rows(of: timeline) {
            let height = row.height(metrics)
            if y >= top - gap / 2, y < top + height + gap / 2 { return row }
            top += height + gap
        }
        return nil
    }

    /// The middle of each gap between rows (and under the ruler), for separator lines.
    static func separatorYs(for timeline: Timeline, _ metrics: TimelineMetrics) -> [CGFloat] {
        let gap = Theme.Spacing.xs
        var y = Theme.Size.rulerHeight + gap / 2
        var ys = [y]
        for row in rows(of: timeline).dropLast() {
            y += row.height(metrics) + gap
            ys.append(y)
        }
        return ys
    }

    /// Whether a touch at `point` (tracks' coordinates) lands on something it
    /// drags: a selected overlay, text or audio item, or a selected main clip's
    /// trim handles. The timeline mustn't start scrolling there, or a fast drag
    /// scrolls before the item's drag gesture begins.
    static func grabsSelection(at point: CGPoint, in timeline: Timeline, metrics: TimelineMetrics, selected: Set<UUID>) -> Bool {
        guard !selected.isEmpty, let row = row(atY: point.y, in: timeline, metrics) else { return false }
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

    /// Up to the height of the default rows plus two more at normal size; past that the timeline scrolls.
    static func visibleHeight(for timeline: Timeline, _ metrics: TimelineMetrics) -> CGFloat {
        let limit = contentHeight(for: Timeline(), TimelineMetrics()) + 2 * Theme.Size.overlayTrackHeight
        return min(contentHeight(for: timeline, metrics), limit)
    }
}
