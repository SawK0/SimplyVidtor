import Foundation
import SwiftData
import Testing
@testable import SimplyVidtor

@MainActor
struct ProjectLibraryTests {
    private let container: ModelContainer
    private let store = MediaStore.temporary()
    private let library: ProjectLibrary

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        library = ProjectLibrary(context: container.mainContext, store: store)
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

    // MARK: - Media

    private func exists(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: file).path(percentEncoded: false))
    }

    @Test func coverComesFromFirstClip() async throws {
        let clip = try MediaImporter.photoClip(writing: TestMedia.pngData(), extension: "png", to: store)
        let project = try library.create(timeline: Timeline(clips: [clip]))
        try await library.updateCover(of: project)
        let cover = try #require(project.coverImageFile)
        #expect(exists(cover))
    }

    @Test func deletingAProjectRemovesOnlyItsUnsharedMedia() throws {
        let shared = try store.write(Data("s".utf8), extension: "mov")
        let own = try store.write(Data("o".utf8), extension: "mov")
        let orphan = try store.write(Data("x".utf8), extension: "mov")

        let keep = try library.create(timeline: Timeline(clips: [.video(mediaFile: shared, duration: 1)]))
        let remove = try library.create(timeline: Timeline(clips: [
            .video(mediaFile: shared, duration: 1),
            .video(mediaFile: own, duration: 1),
        ]))
        _ = keep

        try library.delete(remove)
        #expect(exists(shared))
        #expect(!exists(own))
        #expect(!exists(orphan))
    }

    @Test func duplicatesShareMediaUntilBothAreDeleted() throws {
        let file = try store.write(Data("v".utf8), extension: "mov")
        let original = try library.create(timeline: Timeline(clips: [.video(mediaFile: file, duration: 1)]))
        let copy = try library.duplicate(original)

        try library.delete(original)
        #expect(exists(file))
        try library.delete(copy)
        #expect(!exists(file))
    }
}
