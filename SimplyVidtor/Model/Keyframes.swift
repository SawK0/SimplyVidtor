import Foundation

/// A value that can be blended with another, for keyframes.
nonisolated protocol Interpolatable {
    /// `self` at 0, `other` at 1.
    func mixed(with other: Self, _ t: Double) -> Self
}

nonisolated struct Keyframe<Value: Interpolatable & Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var time: Double
    var value: Value
    /// The curve from this keyframe to the next.
    var easing = Easing.linear

    init(time: Double, value: Value, easing: Easing = .linear) {
        self.time = time
        self.value = value
        self.easing = easing
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Double.self, forKey: .time)
        value = try c.decode(Value.self, forKey: .value)
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .linear
    }
}

/// Values at times, kept sorted. Before the first keyframe the value holds
/// at the first; after the last it holds at the last.
nonisolated struct KeyframeTrack<Value: Interpolatable & Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    /// Keyframes closer than this count as the same one.
    static var tolerance: Double { 0.02 }

    private(set) var keyframes: [Keyframe<Value>] = []

    init(_ keyframes: [Keyframe<Value>] = []) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try c.decodeIfPresent([Keyframe<Value>].self, forKey: .keyframes) ?? [])
    }

    var isEmpty: Bool { keyframes.isEmpty }
    var times: [Double] { keyframes.map(\.time) }

    /// `nil` without keyframes.
    func value(at time: Double) -> Value? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        let next = keyframes.firstIndex { $0.time > time } ?? keyframes.count - 1
        let a = keyframes[next - 1], b = keyframes[next]
        let span = b.time - a.time
        return a.value.mixed(with: b.value, a.easing.value(at: span > 0 ? (time - a.time) / span : 1))
    }

    func index(near time: Double, tolerance: Double = tolerance) -> Int? {
        keyframes.indices
            .filter { abs(keyframes[$0].time - time) <= tolerance }
            .min { abs(keyframes[$0].time - time) < abs(keyframes[$1].time - time) }
    }

    func previous(before time: Double, tolerance: Double = tolerance) -> Keyframe<Value>? {
        keyframes.last { $0.time < time - tolerance }
    }

    func next(after time: Double, tolerance: Double = tolerance) -> Keyframe<Value>? {
        keyframes.first { $0.time > time + tolerance }
    }

    /// Adds a keyframe, or replaces the value of the one already there.
    mutating func set(_ value: Value, at time: Double, tolerance: Double = tolerance) {
        if let index = index(near: time, tolerance: tolerance) {
            keyframes[index].value = value
        } else {
            keyframes.append(Keyframe(time: time, value: value))
            keyframes.sort { $0.time < $1.time }
        }
    }

    /// Returns the removed keyframe's value.
    @discardableResult
    mutating func remove(near time: Double, tolerance: Double = tolerance) -> Value? {
        guard let index = index(near: time, tolerance: tolerance) else { return nil }
        return keyframes.remove(at: index).value
    }

    mutating func setEasing(_ easing: Easing, near time: Double, tolerance: Double = tolerance) {
        guard let index = index(near: time, tolerance: tolerance) else { return }
        keyframes[index].easing = easing
    }

    /// Every time moved by `delta`.
    func shifted(by delta: Double) -> KeyframeTrack {
        KeyframeTrack(keyframes.map { Keyframe(time: $0.time + delta, value: $0.value, easing: $0.easing) })
    }
}

nonisolated extension ClipTransform: Interpolatable {
    /// Fit or fill doesn't blend; it comes from `self`.
    func mixed(with other: ClipTransform, _ t: Double) -> ClipTransform {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        var result = self
        result.scale = mix(scale, other.scale)
        result.x = mix(x, other.x)
        result.y = mix(y, other.y)
        result.rotation = mix(rotation, other.rotation)
        result.opacity = min(max(mix(opacity, other.opacity), 0), 1)
        return result
    }
}
