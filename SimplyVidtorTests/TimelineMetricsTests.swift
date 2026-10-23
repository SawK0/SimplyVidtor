import CoreGraphics
import Testing
@testable import SimplyVidtor

struct TimelineMetricsTests {
    @Test func offsetAndTimeAreInverse() {
        let metrics = TimelineMetrics(pointsPerSecond: 80)
        #expect(metrics.offset(for: 2.5) == 200)
        #expect(metrics.time(forOffset: 200) == 2.5)
        #expect(metrics.width(of: 0.5) == 40)
    }

    @Test(arguments: [
        (CGFloat(400), 0.5),
        (CGFloat(60), 2.0),
        (CGFloat(15), 5.0),
        (CGFloat(1), 120.0),
        (CGFloat(0.1), 300.0),
    ])
    func tickIntervalKeepsLabelsApart(pps: CGFloat, expected: Double) {
        let metrics = TimelineMetrics(pointsPerSecond: pps)
        #expect(metrics.tickInterval == expected)
    }

    @Test func zoomIsClamped() {
        let metrics = TimelineMetrics(pointsPerSecond: 100)
        #expect(metrics.zoomed(by: 2).pointsPerSecond == 200)
        #expect(metrics.zoomed(by: 100).pointsPerSecond == TimelineMetrics.zoomRange.upperBound)
        #expect(metrics.zoomed(by: 0.01).pointsPerSecond == TimelineMetrics.zoomRange.lowerBound)
    }

    // MARK: - Grabbing the selection

    /// The y of the middle of `row`.
    private func y(of row: TimelineLayout.Row, in timeline: Timeline) -> CGFloat {
        let ys = stride(from: CGFloat(0), to: 1000, by: 1).filter { TimelineLayout.row(atY: $0, in: timeline) == row }
        return (ys.first! + ys.last!) / 2
    }

    @Test func selectedOverlaysAndTextAreGrabbedButNotScrolled() {
        var timeline = Timeline()
        timeline.clips = [.video(mediaFile: "a.mov", duration: 10)]
        let overlay = timeline.insertOverlay(.video(mediaFile: "b.mov", duration: 2), at: 3)
        let text = TextItem(text: "Hi", timelineStart: 5, duration: 2)
        timeline.upsertText(text)
        let metrics = TimelineMetrics(pointsPerSecond: 10)
        let videoY = y(of: .track(timeline.track(timeline.overlays[0].trackID)!), in: timeline)
        let textY = y(of: .track(Track.firstText), in: timeline)

        #expect(TimelineLayout.grabsSelection(at: CGPoint(x: 40, y: videoY), in: timeline, metrics: metrics, selected: [overlay]))
        #expect(!TimelineLayout.grabsSelection(at: CGPoint(x: 40, y: videoY), in: timeline, metrics: metrics, selected: []),
                "Unselected items scroll")
        #expect(!TimelineLayout.grabsSelection(at: CGPoint(x: 80, y: videoY), in: timeline, metrics: metrics, selected: [overlay]),
                "Past the overlay scrolls")
        #expect(!TimelineLayout.grabsSelection(at: CGPoint(x: 40, y: textY), in: timeline, metrics: metrics, selected: [overlay]),
                "Other rows scroll")
        #expect(TimelineLayout.grabsSelection(at: CGPoint(x: 60, y: textY), in: timeline, metrics: metrics, selected: [text.id]))
    }

    @Test func aSelectedMainClipIsGrabbedOnlyByItsHandles() {
        var timeline = Timeline()
        let clip = Clip.video(mediaFile: "a.mov", duration: 10)
        timeline.clips = [clip]
        let metrics = TimelineMetrics(pointsPerSecond: 10)
        let mainY = y(of: .main, in: timeline)
        func grabs(_ x: CGFloat) -> Bool {
            TimelineLayout.grabsSelection(at: CGPoint(x: x, y: mainY), in: timeline, metrics: metrics, selected: [clip.id])
        }
        #expect(grabs(5), "Leading handle")
        #expect(grabs(95), "Trailing handle")
        #expect(!grabs(50), "The middle scrolls")
    }
}
