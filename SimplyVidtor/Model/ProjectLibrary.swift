import Foundation
import SwiftData

/// Create, rename, duplicate and delete projects, and keep the media store tidy.
struct ProjectLibrary {
    let context: ModelContext
    let store: MediaStore

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
        try removeUnusedMedia()
    }

    /// Renders a cover from the first clip.
    func updateCover(of project: Project) async throws {
        guard let first = try project.loadTimeline().clips.first else { return }
        project.coverImageFile = try await Thumbnailer.makeCover(for: first, in: store)
        try context.save()
    }

    /// Deletes media that no project or library audio refers to (left by deletes or cancelled imports).
    /// Does nothing if any timeline fails to decode, since its files can't be accounted for.
    func removeUnusedMedia() throws {
        var referenced = Set<String>()
        for project in try context.fetch(FetchDescriptor<Project>()) {
            guard let timeline = try? project.loadTimeline() else { return }
            referenced.formUnion(timeline.clips.map(\.mediaFile))
            referenced.formUnion(timeline.audioItems.map(\.mediaFile))
            if let cover = project.coverImageFile { referenced.insert(cover) }
        }
        referenced.formUnion(try context.fetch(FetchDescriptor<AudioAsset>()).map(\.mediaFile))
        try store.removeFiles(notIn: referenced)
    }
}
