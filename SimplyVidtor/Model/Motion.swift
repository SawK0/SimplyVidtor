import Foundation

/// A cubic-bezier timing curve from (0, 0) to (1, 1), like CSS `cubic-bezier`.
/// In JSON it's a name (`"easeOut"`) or four numbers (`[0.16, 1, 0.3, 1]`).
nonisolated struct Easing: Hashable, Sendable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    static let linear = Easing(x1: 0, y1: 0, x2: 1, y2: 1)
    static let easeIn = Easing(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeOut = Easing(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = Easing(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    /// Fast start, long settle.
    static let snappy = Easing(x1: 0.16, y1: 1, x2: 0.3, y2: 1)
    /// Overshoots, then settles.
    static let back = Easing(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1)

    static let named: [String: Easing] = [
        "linear": .linear, "easeIn": .easeIn, "easeOut": .easeOut, "easeInOut": .easeInOut,
        "snappy": .snappy, "back": .back,
    ]

    /// Control points must keep x in 0...1 so time never runs backwards.
    var isValid: Bool {
        [x1, y1, x2, y2].allSatisfy(\.isFinite) && (0...1).contains(x1) && (0...1).contains(x2)
            && (-2...3).contains(y1) && (-2...3).contains(y2)
    }

    func value(at t: Double) -> Double {
        let t = min(max(t, 0), 1)
        if self == .linear { return t }
        // x(s) is monotonic, so bisect for the s where x(s) = t.
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if Self.bezier(mid, x1, x2) < t { low = mid } else { high = mid }
        }
        return Self.bezier((low + high) / 2, y1, y2)
    }

    private static func bezier(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
    }
}

nonisolated extension Easing: Codable {
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let name = try? c.decode(String.self) {
            guard let easing = Self.named[name] else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown easing \(name)")
            }
            self = easing
            return
        }
        let points = try c.decode([Double].self)
        guard points.count == 4 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Easing needs 4 numbers")
        }
        self.init(x1: points[0], y1: points[1], x2: points[2], y2: points[3])
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        if let name = Self.named.first(where: { $0.value == self })?.key {
            try c.encode(name)
        } else {
            try c.encode([x1, y1, x2, y2])
        }
    }
}

/// Which way a directional animation travels.
nonisolated enum MotionDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right

    var opposite: MotionDirection {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }

    /// Turns an offset authored for `.up` to travel this way.
    func rotate(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .up: (x, y)
        case .right: (-y, x)
        case .down: (-x, -y)
        case .left: (y, -x)
        }
    }
}

nonisolated enum MotionRole: String, Codable, CaseIterable, Sendable {
    case entrance = "in", exit = "out", loop
}

/// How an overlay is drawn at one instant, relative to its resting place.
/// Offsets are fractions of the frame's shorter side (x right, y down);
/// rotation is clockwise in radians; `reveal` is the visible fraction for wipes.
nonisolated struct MotionState: Hashable, Sendable {
    var opacity = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var scale = 1.0
    var rotation = 0.0
    var reveal = 1.0
    /// The visible part grows toward this edge.
    var revealDirection = MotionDirection.right

    static let identity = MotionState()

    var isIdentity: Bool {
        opacity == 1 && offsetX == 0 && offsetY == 0 && scale == 1 && rotation == 0 && reveal >= 1
    }

    func combined(with other: MotionState) -> MotionState {
        MotionState(
            opacity: opacity * other.opacity,
            offsetX: offsetX + other.offsetX,
            offsetY: offsetY + other.offsetY,
            scale: scale * other.scale,
            rotation: rotation + other.rotation,
            reveal: min(reveal, other.reveal),
            revealDirection: other.reveal < reveal ? other.revealDirection : revealDirection
        )
    }
}

/// One point of an animation. Missing values in JSON rest at their defaults.
nonisolated struct MotionKeyframe: Codable, Hashable, Sendable {
    /// Progress through the animation, 0...1.
    var time: Double
    var opacity = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var scale = 1.0
    var rotation = 0.0
    var reveal = 1.0
    /// The curve from this keyframe to the next.
    var easing = Easing.linear

    var state: MotionState {
        MotionState(opacity: opacity, offsetX: offsetX, offsetY: offsetY, scale: scale, rotation: rotation, reveal: reveal)
    }

    init(time: Double, opacity: Double = 1, offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1,
         rotation: Double = 0, reveal: Double = 1, easing: Easing = .linear) {
        self.time = time
        self.opacity = opacity
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.rotation = rotation
        self.reveal = reveal
        self.easing = easing
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            time: try c.decode(Double.self, forKey: .time),
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            offsetX: try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0,
            offsetY: try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0,
            scale: try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1,
            rotation: try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0,
            reveal: try c.decodeIfPresent(Double.self, forKey: .reveal) ?? 1,
            easing: try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .linear
        )
    }
}

/// Keyframes over 0...1 progress. Built-in presets and imported packs share
/// this format. An entrance ends at rest; it plays backwards as an exit.
/// A loop starts and ends at the same state.
nonisolated struct MotionAnimation: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var roles: [MotionRole]
    var keyframes: [MotionKeyframe]
    /// Offsets and wipes follow the chosen direction (authored travelling up).
    var isDirectional = false
    /// Whether strength scales the movement. Off for loops that must line up, like a full spin.
    var hasStrength = true
    /// Above 0, characters animate one after another; their starts spread over
    /// this fraction of the duration (1 = typewriter).
    var characterSpread = 0.0
    var defaultDuration: Double?

    var animatesCharacters: Bool { characterSpread > 0 }

    /// Keyframes are sorted by time when the animation is validated.
    func state(at progress: Double) -> MotionState {
        guard let first = keyframes.first, let last = keyframes.last else { return .identity }
        let p = min(max(progress, 0), 1)
        if p <= first.time { return first.state }
        if p >= last.time { return last.state }
        let next = keyframes.firstIndex { $0.time > p } ?? keyframes.count - 1
        let a = keyframes[next - 1], b = keyframes[next]
        let span = b.time - a.time
        let t = a.easing.value(at: span > 0 ? (p - a.time) / span : 1)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return MotionState(
            opacity: min(max(mix(a.opacity, b.opacity), 0), 1),
            offsetX: mix(a.offsetX, b.offsetX),
            offsetY: mix(a.offsetY, b.offsetY),
            scale: max(mix(a.scale, b.scale), 0),
            rotation: mix(a.rotation, b.rotation),
            reveal: min(max(mix(a.reveal, b.reveal), 0), 1)
        )
    }

    init(id: String, name: String, roles: [MotionRole], keyframes: [MotionKeyframe], isDirectional: Bool = false,
         hasStrength: Bool = true, characterSpread: Double = 0, defaultDuration: Double? = nil) {
        self.id = id
        self.name = name
        self.roles = roles
        self.keyframes = keyframes
        self.isDirectional = isDirectional
        self.hasStrength = hasStrength
        self.characterSpread = characterSpread
        self.defaultDuration = defaultDuration
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            roles: try c.decode([MotionRole].self, forKey: .roles),
            keyframes: try c.decode([MotionKeyframe].self, forKey: .keyframes),
            isDirectional: try c.decodeIfPresent(Bool.self, forKey: .isDirectional) ?? false,
            hasStrength: try c.decodeIfPresent(Bool.self, forKey: .hasStrength) ?? true,
            characterSpread: try c.decodeIfPresent(Double.self, forKey: .characterSpread) ?? 0,
            defaultDuration: try c.decodeIfPresent(Double.self, forKey: .defaultDuration)
        )
    }
}

/// An animation as used by one overlay, with the user's settings. The
/// animation is embedded so the project renders without its pack.
nonisolated struct AppliedMotion: Codable, Hashable, Sendable {
    static let durationRange: ClosedRange<Double> = 0.1...3
    static let strengthRange: ClosedRange<Double> = 0.25...2
    static let defaultDuration: Double = 0.6
    static let defaultLoopDuration: Double = 1.2

    var animation: MotionAnimation
    var duration: Double
    var direction = MotionDirection.up
    var strength = 1.0
    /// Remaps progress before the keyframes are read.
    var easing = Easing.linear

    init(_ animation: MotionAnimation, role: MotionRole) {
        self.animation = animation
        duration = animation.defaultDuration ?? (role == .loop ? Self.defaultLoopDuration : Self.defaultDuration)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animation = try c.decode(MotionAnimation.self, forKey: .animation)
        duration = try c.decode(Double.self, forKey: .duration)
        direction = try c.decodeIfPresent(MotionDirection.self, forKey: .direction) ?? .up
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 1
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .linear
    }

    var clamped: AppliedMotion {
        var motion = self
        motion.duration = min(max(duration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
        motion.strength = min(max(strength, Self.strengthRange.lowerBound), Self.strengthRange.upperBound)
        return motion
    }

    /// The state at `progress` (0...1). Exits play the animation backwards,
    /// still travelling the chosen way. `character` is (index, count) for
    /// per-character animations; other animations ignore characters, and
    /// per-character ones are identity for the whole item.
    func state(at progress: Double, role: MotionRole, character: (index: Int, count: Int)? = nil) -> MotionState {
        guard animation.animatesCharacters == (character != nil) else { return .identity }
        var p = min(max(progress, 0), 1)
        if let character {
            let spread = min(max(animation.characterSpread, 0), 1)
            let start = character.count > 1 ? spread * Double(character.index) / Double(character.count - 1) : 0
            let window = 1 - spread
            p = window > 0 ? min(max((p - start) / window, 0), 1) : (p >= start ? 1 : 0)
        }
        p = easing.value(at: p)
        var direction = direction
        if role == .exit {
            p = 1 - p
            direction = direction.opposite
        }
        var state = animation.state(at: p)
        if animation.hasStrength {
            state.offsetX *= strength
            state.offsetY *= strength
            state.rotation *= strength
            state.scale = max(1 + (state.scale - 1) * strength, 0)
        }
        if animation.isDirectional {
            (state.offsetX, state.offsetY) = direction.rotate(x: state.offsetX, y: state.offsetY)
            state.revealDirection = direction
        } else {
            state.revealDirection = role == .exit ? .left : .right
        }
        return state
    }
}

/// An overlay's In, Out and Loop animations.
nonisolated struct TextMotion: Codable, Hashable, Sendable {
    var entrance: AppliedMotion?
    var exit: AppliedMotion?
    var loop: AppliedMotion?

    var isEmpty: Bool { entrance == nil && exit == nil && loop == nil }

    subscript(role: MotionRole) -> AppliedMotion? {
        get {
            switch role {
            case .entrance: entrance
            case .exit: exit
            case .loop: loop
            }
        }
        set {
            switch role {
            case .entrance: entrance = newValue?.clamped
            case .exit: exit = newValue?.clamped
            case .loop: loop = newValue?.clamped
            }
        }
    }

    /// Every embedded animation.
    var animations: [MotionAnimation] {
        [entrance, exit, loop].compactMap { $0?.animation }
    }

    /// In and Out lengths for an item `duration` long; scaled down together
    /// when they don't fit.
    func windows(duration: Double) -> (entrance: Double, exit: Double) {
        let a = entrance?.duration ?? 0, b = exit?.duration ?? 0
        guard a + b > duration, a + b > 0 else { return (a, b) }
        let fit = max(duration, 0) / (a + b)
        return (a * fit, b * fit)
    }

    /// Which animation plays `time` seconds into an item `duration` long, and how far through it.
    func active(at time: Double, duration: Double) -> [(role: MotionRole, motion: AppliedMotion, progress: Double)] {
        let (inLength, outLength) = windows(duration: duration)
        if let entrance, time < inLength {
            return [(.entrance, entrance, time / inLength)]
        }
        if let exit, time > duration - outLength, outLength > 0 {
            return [(.exit, exit, (time - (duration - outLength)) / outLength)]
        }
        if let loop, loop.duration > 0 {
            let phase = (time - inLength).truncatingRemainder(dividingBy: loop.duration) / loop.duration
            return [(.loop, loop, max(phase, 0))]
        }
        return []
    }

    /// The whole-item state `time` seconds into an item `duration` long.
    func state(at time: Double, duration: Double) -> MotionState {
        active(at: time, duration: duration).reduce(.identity) { state, entry in
            state.combined(with: entry.motion.state(at: entry.progress, role: entry.role))
        }
    }

    /// Whether characters move separately at `time`.
    func animatesCharacters(at time: Double, duration: Double) -> Bool {
        active(at: time, duration: duration).contains { $0.motion.animation.animatesCharacters }
    }

    /// The state of character `index` of `count` at `time`.
    func characterState(at time: Double, duration: Double, index: Int, count: Int) -> MotionState {
        active(at: time, duration: duration).reduce(.identity) { state, entry in
            state.combined(with: entry.motion.state(at: entry.progress, role: entry.role, character: (index, count)))
        }
    }
}
