import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    /// File name of the cover thumbnail inside the app's media folder.
    var coverImageFile: String?
    /// JSON-encoded `Timeline`. Stored as data so timeline changes need no SwiftData migration.
    private var timelineData: Data

    init(name: String, timeline: Timeline = Timeline(), now: Date = .now) throws {
        self.id = UUID()
        self.name = name
        self.createdAt = now
        self.modifiedAt = now
        self.timelineData = try JSONEncoder().encode(timeline)
    }

    /// Throws rather than returning an empty timeline, so a decode failure
    /// can never be autosaved over the user's edit.
    func loadTimeline() throws -> Timeline {
        try JSONDecoder().decode(Timeline.self, from: timelineData)
    }

    func save(_ timeline: Timeline, now: Date = .now) throws {
        timelineData = try JSONEncoder().encode(timeline)
        modifiedAt = now
    }

    /// Copy with a fresh id. Media files are shared, not copied.
    func duplicate(named newName: String, now: Date = .now) throws -> Project {
        let copy = try Project(name: newName, timeline: loadTimeline(), now: now)
        copy.coverImageFile = coverImageFile
        return copy
    }
}
