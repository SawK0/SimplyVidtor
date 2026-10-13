import Foundation

/// Canvas shape for the whole project. `nil` on the timeline means "match the first clip".
nonisolated enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case portrait, landscape, square, fourByFive, fourByThree

    /// Width over height.
    var value: Double {
        switch self {
        case .portrait: 9.0 / 16.0
        case .landscape: 16.0 / 9.0
        case .square: 1
        case .fourByFive: 4.0 / 5.0
        case .fourByThree: 4.0 / 3.0
        }
    }

    var title: String {
        switch self {
        case .portrait: "9:16"
        case .landscape: "16:9"
        case .square: "1:1"
        case .fourByFive: "4:5"
        case .fourByThree: "4:3"
        }
    }
}

/// The project's frame, like a sequence's settings in a desktop editor.
nonisolated struct ProjectFormat: Codable, Hashable, Sendable {
    /// Shorter side in pixels.
    static let resolutions = [720, 1080, 2160]
    static let frameRates = [24, 25, 30, 60]

    /// `nil` matches the first clip's shape.
    var aspectRatio: AspectRatio?
    var resolution = 1080
    var frameRate = 30

    static func title(ofResolution resolution: Int) -> String {
        resolution == 2160 ? "4K" : "\(resolution)p"
    }
}

/// Part of a frame to keep, normalized to 0...1 with the origin at the top left.
nonisolated struct CropRect: Codable, Hashable, Sendable {
    static let full = CropRect(x: 0, y: 0, width: 1, height: 1)
    /// Smallest side, as a fraction of the frame.
    static let minimumSide = 0.1

    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var isFull: Bool { abs(x) < 1e-6 && abs(y) < 1e-6 && abs(width - 1) < 1e-6 && abs(height - 1) < 1e-6 }

    /// The same region after the frame turns 90° clockwise.
    var rotatedClockwise: CropRect {
        CropRect(x: 1 - maxY, y: x, width: height, height: width)
    }

    /// Kept inside the frame and no smaller than `minimumSide`.
    var clamped: CropRect {
        let w = min(max(width, Self.minimumSide), 1)
        let h = min(max(height, Self.minimumSide), 1)
        return CropRect(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h), width: w, height: h)
    }

    /// The largest centred rect with `ratio` (width over height, in pixels)
    /// inside a frame of `frameAspect` (width over height).
    static func centered(ratio: Double, frameAspect: Double) -> CropRect {
        let normalized = ratio / frameAspect
        let (w, h) = normalized < 1 ? (normalized, 1.0) : (1.0, 1 / normalized)
        return CropRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    enum Corner: CaseIterable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }

    func moved(dx: Double, dy: Double) -> CropRect {
        CropRect(x: min(max(x + dx, 0), 1 - width), y: min(max(y + dy, 0), 1 - height), width: width, height: height)
    }

    /// Drags `corner` to `point`, keeping the opposite corner fixed. With a
    /// `ratio` (normalized width over height) the rect keeps that shape.
    func resized(_ corner: Corner, to point: (x: Double, y: Double), ratio: Double? = nil) -> CropRect {
        let anchorX = corner == .topLeft || corner == .bottomLeft ? maxX : x
        let anchorY = corner == .topLeft || corner == .topRight ? maxY : y
        let growsLeft = anchorX == maxX
        let growsUp = anchorY == maxY
        // Room available from the anchor to the frame edge in the drag direction.
        let roomX = growsLeft ? anchorX : 1 - anchorX
        let roomY = growsUp ? anchorY : 1 - anchorY
        var w = min(max(growsLeft ? anchorX - point.x : point.x - anchorX, Self.minimumSide), roomX)
        var h = min(max(growsUp ? anchorY - point.y : point.y - anchorY, Self.minimumSide), roomY)
        if let ratio {
            // Follow whichever side the finger pulls further, then fit in the room.
            if w / ratio > h { h = w / ratio } else { w = h * ratio }
            let fit = min(1, roomX / w, roomY / h)
            w *= fit
            h *= fit
        }
        return CropRect(x: growsLeft ? anchorX - w : anchorX, y: growsUp ? anchorY - h : anchorY, width: w, height: h)
    }
}
