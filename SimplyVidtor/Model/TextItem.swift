import Foundation

nonisolated enum TextFont: String, Codable, CaseIterable, Sendable {
    case system, rounded, serif, mono
}

nonisolated enum TextBackground: String, Codable, CaseIterable, Sendable {
    case none, box, outline
}

/// A caption over the video. Position is the text's centre, normalized 0...1
/// from the top left of the frame; `size` is the font size as a fraction of
/// the frame's shorter side.
nonisolated struct TextItem: Codable, Identifiable, Hashable, Sendable {
    static let defaultDuration: Double = 3
    static let sizeRange: ClosedRange<Double> = 0.03...0.3
    /// White, yellow, black, red, blue, green, pink, orange as 0xRRGGBB.
    static let palette: [UInt32] = [0xFFFFFF, 0xFFCC00, 0x111111, 0xFF453A, 0x0A84FF, 0x30D158, 0xFF6FB5, 0xFF9F0A]

    var id = UUID()
    var text: String
    var timelineStart: Double
    var duration: Double = defaultDuration
    var x: Double = 0.5
    var y: Double = 0.5
    var size: Double = 0.08
    /// Clockwise, in radians.
    var rotation: Double = 0
    var font: TextFont = .system
    var color: UInt32 = 0xFFFFFF
    var background: TextBackground = .none

    var timelineEnd: Double { timelineStart + duration }

    func isVisible(at time: Double) -> Bool {
        time >= timelineStart && time < timelineEnd
    }
}
