import Foundation

/// Placeholder until the SwiftData `Project` model exists.
struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    var duration: TimeInterval
    var modified: Date

    init(id: UUID = UUID(), name: String, duration: TimeInterval, modified: Date = .now) {
        self.id = id
        self.name = name
        self.duration = duration
        self.modified = modified
    }

    static func untitled() -> ProjectSummary {
        ProjectSummary(name: String(localized: "Untitled Project"), duration: 0)
    }

    static let samples: [ProjectSummary] = [
        ProjectSummary(name: "Beach Day", duration: 42, modified: .now.addingTimeInterval(-3_600)),
        ProjectSummary(name: "Tokyo Trip", duration: 185, modified: .now.addingTimeInterval(-86_400)),
        ProjectSummary(name: "Birthday", duration: 67, modified: .now.addingTimeInterval(-3 * 86_400)),
        ProjectSummary(name: "Morning Run", duration: 24, modified: .now.addingTimeInterval(-7 * 86_400)),
    ]
}
