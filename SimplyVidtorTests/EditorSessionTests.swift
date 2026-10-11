import Foundation
import Testing
@testable import SimplyVidtor

@MainActor
struct EditorSessionTests {
    let store = MediaStore.temporary()

    private func makeSession(clips: [Clip] = [.video(mediaFile: "a.mov", duration: 4)]) throws -> EditorSession {
        let project = try Project(name: "Test", timeline: Timeline(clips: clips))
        return try EditorSession(project: project, store: store)
    }

    @Test func loadsProjectTimeline() throws {
        let session = try makeSession()
        #expect(session.timeline.clips.count == 1)
        #expect(session.duration == 4)
    }

    @Test func updateSavesToProject() async throws {
        let session = try makeSession()
        await session.update { $0.insert([.photo(mediaFile: "p.heic")], at: 1) }
        #expect(session.timeline.clips.count == 2)
        #expect(try session.project.loadTimeline() == session.timeline)
    }

    @Test func noOpUpdateDoesNotTouchProject() async throws {
        let session = try makeSession()
        let modified = session.project.modifiedAt
        await session.update { _ in }
        #expect(session.project.modifiedAt == modified)
    }

    @Test func seekIsClampedToTimeline() async throws {
        let session = try makeSession()
        await session.rebuild()
        await session.seek(to: 99)
        #expect(session.currentTime == 4)
        await session.seek(to: -3)
        #expect(session.currentTime == 0)
    }

    @Test func scrubUpdatesTimeImmediatelyAndClamps() async throws {
        let session = try makeSession()
        await session.rebuild()
        session.scrub(to: 1.5)
        #expect(session.currentTime == 1.5)
        session.scrub(to: 2)
        session.scrub(to: 50)
        #expect(session.currentTime == 4)
    }

    @Test func togglePlaybackFlipsState() async throws {
        let session = try makeSession()
        await session.rebuild()
        session.togglePlayback()
        #expect(session.isPlaying)
        session.togglePlayback()
        #expect(!session.isPlaying)
    }
}
