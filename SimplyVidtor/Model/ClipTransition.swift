import Foundation

nonisolated enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case crossfade, dipToBlack

    var title: String {
        switch self {
        case .crossfade: String(localized: "Cross-fade")
        case .dipToBlack: String(localized: "Dip to Black")
        }
    }
}

/// How a clip blends into the next one. The clips overlap by the transition,
/// so it shortens the timeline.
nonisolated struct ClipTransition: Codable, Hashable, Sendable {
    static let durationRange: ClosedRange<Double> = 0.2...2
    static let defaultDuration = 0.5

    var kind: TransitionKind
    var duration: Double = defaultDuration
}
