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
    /// Times are seconds from the item's start. When there are any, they
    /// replace the static position, size and rotation.
    var keyframes = KeyframeTrack<TextPlacement>()

    var placement: TextPlacement {
        get { TextPlacement(x: x, y: y, size: size, rotation: rotation) }
        set {
            x = newValue.x
            y = newValue.y
            size = newValue.size
            rotation = newValue.rotation
        }
    }

    /// Position, size and rotation at timeline `time`.
    func placement(at time: Double) -> TextPlacement {
        keyframes.value(at: time - timelineStart) ?? placement
    }

    /// The item as drawn at timeline `time`, with keyframes applied.
    func placed(at time: Double) -> TextItem {
        guard !keyframes.isEmpty else { return self }
        var item = self
        item.placement = placement(at: time)
        return item
    }

    /// Sets the placement, or with keyframes, the keyframe at timeline `time`.
    func setting(_ placement: TextPlacement, at time: Double) -> TextItem {
        var item = self
        if keyframes.isEmpty {
            item.placement = placement.clamped
        } else {
            item.keyframes.set(placement.clamped, at: time - timelineStart)
        }
        return item
    }

    /// Adds a keyframe holding the current placement at timeline `time`, or
    /// removes the one there. Removing the last keyframe keeps its placement.
    func togglingKeyframe(at time: Double) -> TextItem {
        var item = self
        if let removed = item.keyframes.remove(near: time - timelineStart) {
            if item.keyframes.isEmpty { item.placement = removed }
        } else {
            item.keyframes.set(placement(at: time), at: time - timelineStart)
        }
        return item
    }

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
        // Keyframes stay where they were on the timeline.
        item.keyframes = keyframes.shifted(by: timelineStart - item.timelineStart)
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
            motion: try c.decodeIfPresent(TextMotion.self, forKey: .motion) ?? TextMotion(),
            keyframes: try c.decodeIfPresent(KeyframeTrack<TextPlacement>.self, forKey: .keyframes) ?? KeyframeTrack()
        )
    }
}

/// Where a text item sits: the values its keyframes animate.
nonisolated struct TextPlacement: Codable, Hashable, Sendable, Interpolatable {
    var x: Double
    var y: Double
    var size: Double
    var rotation: Double

    var clamped: TextPlacement {
        TextPlacement(x: min(max(x, 0), 1), y: min(max(y, 0), 1),
                      size: min(max(size, TextItem.sizeRange.lowerBound), TextItem.sizeRange.upperBound),
                      rotation: rotation)
    }

    func mixed(with other: TextPlacement, _ t: Double) -> TextPlacement {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return TextPlacement(x: mix(x, other.x), y: mix(y, other.y), size: mix(size, other.size), rotation: mix(rotation, other.rotation))
    }
}
