import Foundation
import SwiftData
import Testing
@testable import SimplyVidtor

@MainActor
struct ProjectLibraryTests {
    private let container: ModelContainer
    private let library: ProjectLibrary

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        library = ProjectLibrary(context: container.mainContext)
    }

    private func allProjects() throws -> [Project] {
        try container.mainContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)]))
    }

    @Test func createInsertsUntitledProject() throws {
        let project = try library.create()
        #expect(project.name == "Untitled Project")
        #expect(try allProjects().count == 1)
    }

    @Test func renameTrimsWhitespace() throws {
        let project = try library.create()
        try library.rename(project, to: "  Beach Day \n")
        #expect(project.name == "Beach Day")
    }

    @Test func renameIgnoresBlankNames() throws {
        let project = try library.create()
        try library.rename(project, to: "   ")
        #expect(project.name == "Untitled Project")
    }

    @Test func renameBumpsModifiedDate() throws {
        let project = try library.create()
        project.modifiedAt = .distantPast
        try library.rename(project, to: "Trip")
        #expect(project.modifiedAt > .distantPast)
    }

    @Test func duplicateAddsCopyWithSuffix() throws {
        let timeline = Timeline(clips: [.video(mediaFile: "a.mov", duration: 4)])
        let project = try library.create(timeline: timeline)
        try library.rename(project, to: "Trip")

        let copy = try library.duplicate(project)
        #expect(copy.name == "Trip copy")
        #expect(try copy.loadTimeline() == timeline)
        #expect(try allProjects().map(\.name) == ["Trip", "Trip copy"])
    }

    @Test func deleteRemovesProject() throws {
        let keep = try library.create()
        let remove = try library.create()
        try library.delete(remove)
        let remaining = try allProjects()
        #expect(remaining.count == 1)
        #expect(remaining.first === keep)
    }
}
