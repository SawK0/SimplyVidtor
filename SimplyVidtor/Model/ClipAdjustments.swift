import Foundation

/// Manual color corrections. Each value is -1...1 with 0 meaning unchanged.
nonisolated struct ClipAdjustments: Codable, Hashable, Sendable {
    static let range: ClosedRange<Double> = -1...1

    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0

    var isIdentity: Bool { self == ClipAdjustments() }

    enum Parameter: String, CaseIterable, Sendable {
        case brightness, contrast, saturation, warmth

        var keyPath: WritableKeyPath<ClipAdjustments, Double> {
            switch self {
            case .brightness: \.brightness
            case .contrast: \.contrast
            case .saturation: \.saturation
            case .warmth: \.warmth
            }
        }
    }

    subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = min(max(newValue, Self.range.lowerBound), Self.range.upperBound) }
    }
}
