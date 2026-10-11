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

    @Test func selectTogglesAndClears() throws {
        let session = try makeSession()
        let id = session.timeline.clips[0].id
        session.select(id)
        #expect(session.selectedClipID == id)
        session.select(id)
        #expect(session.selectedClipID == nil)
        session.select(id)
        session.select(nil)
        #expect(session.selectedClipID == nil)
    }

    @Test func removingSelectedClipClearsSelection() async throws {
        let session = try makeSession()
        let id = session.timeline.clips[0].id
        session.select(id)
        await session.update { $0.removeClip(id) }
        #expect(session.selectedClipID == nil)
    }

    @Test func interactiveEditUpdatesLiveAndSavesOnce() async throws {
        let session = try makeSession()
        let id = session.timeline.clips[0].id
        session.beginInteractiveEdit()
        #expect(session.isEditingInteractively)

        session.updateInteractiveEdit { $0.trimEnd(ofClip: id, toSource: 3) }
        session.updateInteractiveEdit { $0.trimEnd(ofClip: id, toSource: 2) }
        #expect(session.duration == 2, "Each update starts from the pre-drag timeline")
        #expect(try session.project.loadTimeline().duration == 4, "Nothing saved mid-drag")

        await session.endInteractiveEdit()
        #expect(!session.isEditingInteractively)
        #expect(try session.project.loadTimeline().duration == 2)
    }

    @Test func cancelInteractiveEditRestores() throws {
        let session = try makeSession()
        let id = session.timeline.clips[0].id
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { $0.trimEnd(ofClip: id, toSource: 1) }
        session.cancelInteractiveEdit()
        #expect(session.duration == 4)
        #expect(!session.isEditingInteractively)
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
