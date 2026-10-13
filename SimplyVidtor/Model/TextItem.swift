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
    /// An emoji sticker: drawn as is, without color or background.
    var isSticker = false
    var motion = TextMotion()

    var timelineEnd: Double { timelineStart + duration }

    func isVisible(at time: Double) -> Bool {
        time >= timelineStart && time < timelineEnd
    }

    static let minimumDuration: Double = 0.1
    static let stickerSize = 0.2
    static let stickers = ["😀", "😂", "😍", "🥳", "😎", "🤩", "😭", "🤔", "👍", "👏", "🙌", "🔥",
                           "❤️", "✨", "🎉", "⭐️", "💯", "🌈", "☀️", "🌙", "🎂", "🎵", "📍", "✈️"]

    static func sticker(_ emoji: String, at time: Double) -> TextItem {
        TextItem(text: emoji, timelineStart: time, size: stickerSize, isSticker: true)
    }

    /// Same length, starting at `start` (not before 0).
    func moved(toStart start: Double) -> TextItem {
        var item = self
        item.timelineStart = max(start, 0)
        return item
    }

    /// Moves the start, keeping the end fixed.
    func trimmingStart(to start: Double) -> TextItem {
        var item = self
        item.timelineStart = min(max(start, 0), timelineEnd - Self.minimumDuration)
        item.duration = timelineEnd - item.timelineStart
        return item
    }

    /// Moves the end, keeping the start fixed.
    func trimmingEnd(to end: Double) -> TextItem {
        var item = self
        item.duration = max(end - timelineStart, Self.minimumDuration)
        return item
    }
}

nonisolated extension TextItem {
    /// Fields added after the first release are decoded leniently.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: try c.decode(String.self, forKey: .text),
            timelineStart: try c.decode(Double.self, forKey: .timelineStart),
            duration: try c.decode(Double.self, forKey: .duration),
            x: try c.decode(Double.self, forKey: .x),
            y: try c.decode(Double.self, forKey: .y),
            size: try c.decode(Double.self, forKey: .size),
            rotation: try c.decode(Double.self, forKey: .rotation),
            font: try c.decode(TextFont.self, forKey: .font),
            color: try c.decode(UInt32.self, forKey: .color),
            background: try c.decode(TextBackground.self, forKey: .background),
            isSticker: try c.decodeIfPresent(Bool.self, forKey: .isSticker) ?? false,
            motion: try c.decodeIfPresent(TextMotion.self, forKey: .motion) ?? TextMotion()
        )
    }
}
