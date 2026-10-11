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
}
