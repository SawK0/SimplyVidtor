import Foundation
import SwiftData

/// Create, rename, duplicate and delete projects in a model context.
struct ProjectLibrary {
    let context: ModelContext

    @discardableResult
    func create(timeline: Timeline = Timeline()) throws -> Project {
        let project = try Project(name: String(localized: "Untitled Project"), timeline: timeline)
        context.insert(project)
        try context.save()
        return project
    }

    /// Ignores names that are empty after trimming whitespace.
    func rename(_ project: Project, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != project.name else { return }
        project.name = name
        project.modifiedAt = .now
        try context.save()
    }

    @discardableResult
    func duplicate(_ project: Project) throws -> Project {
        let copy = try project.duplicate(named: String(localized: "\(project.name) copy"))
        context.insert(copy)
        try context.save()
        return copy
    }

    func delete(_ project: Project) throws {
        context.delete(project)
        try context.save()
    }
}
