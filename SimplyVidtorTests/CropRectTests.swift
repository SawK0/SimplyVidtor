import Testing
@testable import SimplyVidtor

struct CropRectTests {
    @Test func rotatingLeftHalfClockwiseGivesTopHalf() {
        let left = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        #expect(left.rotatedClockwise == CropRect(x: 0, y: 0, width: 1, height: 0.5))
    }

    @Test func fourTurnsComeBackToTheStart() {
        let rect = CropRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let turned = rect.rotatedClockwise.rotatedClockwise.rotatedClockwise.rotatedClockwise
        #expect(abs(turned.x - rect.x) < 1e-9 && abs(turned.y - rect.y) < 1e-9)
        #expect(abs(turned.width - rect.width) < 1e-9 && abs(turned.height - rect.height) < 1e-9)
    }

    @Test func centeredSquareInLandscapeFrame() {
        let rect = CropRect.centered(ratio: 1, frameAspect: 16.0 / 9.0)
        #expect(abs(rect.width - 9.0 / 16.0) < 1e-9 && rect.height == 1)
        #expect(abs(rect.x - (1 - 9.0 / 16.0) / 2) < 1e-9 && rect.y == 0)
    }

    @Test func clampedStaysInsideAndAboveMinimum() {
        let rect = CropRect(x: 0.95, y: -0.2, width: 0.01, height: 2).clamped
        #expect(rect == CropRect(x: 0.9, y: 0, width: 0.1, height: 1))
    }

    @Test func movingStopsAtTheEdges() {
        let rect = CropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        #expect(rect.moved(dx: 1, dy: -1) == CropRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    @Test func resizingKeepsTheOppositeCorner() {
        let rect = CropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let resized = rect.resized(.topLeft, to: (x: 0.1, y: 0.3))
        #expect(abs(resized.maxX - 0.7) < 1e-9 && abs(resized.maxY - 0.7) < 1e-9)
        #expect(abs(resized.x - 0.1) < 1e-9 && abs(resized.y - 0.3) < 1e-9)
    }

    @Test func resizingWithRatioKeepsShapeAndStaysInFrame() {
        let rect = CropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let resized = rect.resized(.bottomRight, to: (x: 1.5, y: 0.7), ratio: 1)
        #expect(abs(resized.width - resized.height) < 1e-9)
        #expect(resized.maxX <= 1 + 1e-9 && resized.maxY <= 1 + 1e-9)
        #expect(resized.x == 0.2 && resized.y == 0.2)
    }
}
