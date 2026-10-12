import Foundation

nonisolated enum FilterPreset: String, Codable, CaseIterable, Sendable {
    case vivid, warm, cool, chrome, fade, instant, mono, noir

    var title: String {
        switch self {
        case .vivid: String(localized: "Vivid")
        case .warm: String(localized: "Warm")
        case .cool: String(localized: "Cool")
        case .chrome: String(localized: "Chrome")
        case .fade: String(localized: "Fade")
        case .instant: String(localized: "Instant")
        case .mono: String(localized: "Mono")
        case .noir: String(localized: "Noir")
        }
    }
}

/// A look applied to a clip, blended with the original by `intensity` (0...1).
nonisolated struct ClipFilter: Codable, Hashable, Sendable {
    var preset: FilterPreset
    var intensity: Double = 1
}
