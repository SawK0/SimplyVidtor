import Foundation
import SwiftData
import Testing
@testable import SimplyVidtor

@MainActor
struct ProjectTests {
    private let timeline = Timeline(clips: [.video(mediaFile: "a.mov", duration: 4)])

    @Test func savesAndLoadsTimeline() throws {
        let project = try Project(name: "Trip")
        #expect(try project.loadTimeline() == Timeline())

        let later = Date(timeIntervalSince1970: 1_000)
        try project.save(timeline, now: later)
        #expect(try project.loadTimeline() == timeline)
        #expect(project.modifiedAt == later)
    }

    @Test func duplicateCopiesContentWithNewIdentity() throws {
        let project = try Project(name: "Trip", timeline: timeline)
        project.coverImageFile = "cover.jpg"

        let copy = try project.duplicate(named: "Trip copy")
        #expect(copy.id != project.id)
        #expect(copy.name == "Trip copy")
        #expect(copy.coverImageFile == "cover.jpg")
        #expect(try copy.loadTimeline() == timeline)
    }

    @Test func persistsInSwiftData() throws {
        let container = try ModelContainer(
            for: Project.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let project = try Project(name: "Trip", timeline: timeline)
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Project>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Trip")
        #expect(try fetched.first?.loadTimeline() == timeline)
    }
}
