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

    @Test func splitAtPlayheadSelectsRightPart() async throws {
        let session = try makeSession()
        await session.rebuild()
        await session.seek(to: 1)
        #expect(session.canSplit)
        await session.splitAtPlayhead()
        #expect(session.timeline.clips.count == 2)
        #expect(session.selectedClipID == session.timeline.clips[1].id)
    }

    @Test func duplicateAndDeleteSelected() async throws {
        let session = try makeSession()
        let original = session.timeline.clips[0].id
        session.select(original)
        await session.duplicateSelected()
        #expect(session.timeline.clips.count == 2)
        #expect(session.selectedClipID == session.timeline.clips[1].id)

        await session.deleteSelected()
        #expect(session.timeline.clips.map(\.id) == [original])
        #expect(session.selectedClipID == nil)
    }

    @Test func actionsWithoutSelectionDoNothing() async throws {
        let session = try makeSession()
        await session.duplicateSelected()
        await session.deleteSelected()
        #expect(session.timeline.clips.count == 1)
    }

    @Test func insertAtPlayheadPlacesClipsAndAudio() async throws {
        let session = try makeSession()
        await session.rebuild()
        await session.seek(to: 3) // second half of the 4 s clip
        let audio = AudioItem(mediaFile: "song.m4a", mediaDuration: 10)
        await session.insertAtPlayhead([.photo(mediaFile: "p.heic")], audio: audio)

        #expect(session.timeline.clips.map(\.mediaFile) == ["a.mov", "p.heic"])
        #expect(session.timeline.audioItems.first?.timelineStart == 3)
        #expect(session.currentTime == 4, "Playhead moves to the inserted clip")
    }

    @Test func undoAndRedoRestoreSnapshots() async throws {
        let session = try makeSession()
        #expect(!session.canUndo)
        await session.update { $0.insert([.photo(mediaFile: "p.heic")], at: 1) }
        await session.update { $0.removeClip($0.clips[0].id) }
        #expect(session.timeline.clips.map(\.mediaFile) == ["p.heic"])

        await session.undo()
        #expect(session.timeline.clips.map(\.mediaFile) == ["a.mov", "p.heic"])
        await session.undo()
        #expect(session.timeline.clips.map(\.mediaFile) == ["a.mov"])
        #expect(!session.canUndo)
        #expect(try session.project.loadTimeline() == session.timeline, "Undo is saved")

        await session.redo()
        #expect(session.timeline.clips.count == 2)
        #expect(session.canRedo)
    }

    @Test func newEditClearsRedo() async throws {
        let session = try makeSession()
        await session.update { $0.insert([.photo(mediaFile: "p.heic")], at: 1) }
        await session.undo()
        #expect(session.canRedo)
        await session.update { $0.insert([.photo(mediaFile: "q.heic")], at: 0) }
        #expect(!session.canRedo)
    }

    @Test func dragIsOneUndoStep() async throws {
        let session = try makeSession()
        let id = session.timeline.clips[0].id
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { $0.trimEnd(ofClip: id, toSource: 3) }
        session.updateInteractiveEdit { $0.trimEnd(ofClip: id, toSource: 2) }
        await session.endInteractiveEdit()

        await session.undo()
        #expect(session.duration == 4)
        #expect(!session.canUndo)
    }

    @Test func cancelledDragAddsNoHistory() throws {
        let session = try makeSession()
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { $0.trimEnd(ofClip: $0.clips[0].id, toSource: 1) }
        session.cancelInteractiveEdit()
        #expect(!session.canUndo)
    }

    @Test func historyIsCapped() async throws {
        let session = try makeSession()
        for i in 0..<(EditorSession.historyLimit + 5) {
            await session.update { $0.insert([.photo(mediaFile: "\(i).heic")], at: 0) }
        }
        var undos = 0
        while session.canUndo {
            await session.undo()
            undos += 1
        }
        #expect(undos == EditorSession.historyLimit)
    }

    @Test func undoClearsSelectionOfVanishedClip() async throws {
        let session = try makeSession()
        await session.update { $0.insert([.photo(mediaFile: "p.heic")], at: 1) }
        session.select(session.timeline.clips[1].id)
        await session.undo()
        #expect(session.selectedClipID == nil)
    }

    @Test func togglePlaybackFlipsState() async throws {
        let session = try makeSession()
        await session.rebuild()
        session.togglePlayback()
        #expect(session.isPlaying)
        session.togglePlayback()
        #expect(!session.isPlaying)
    }

    @Test func textEditCommitsAsOneUndoStep() async throws {
        let session = try makeSession()
        var item = TextItem(text: "H", timelineStart: 0)
        session.beginInteractiveEdit()
        session.updateInteractiveEdit { $0.upsertText(item) }
        item.text = "Hello"
        session.updateInteractiveEdit { $0.upsertText(item) }
        await session.endInteractiveEdit()
        #expect(session.timeline.textItems.map(\.text) == ["Hello"])
        #expect(try session.project.loadTimeline().textItems.count == 1)

        await session.undo()
        #expect(session.timeline.textItems.isEmpty)
    }

    @Test func selectingTextClearsClipSelection() throws {
        let session = try makeSession()
        session.select(session.timeline.clips[0].id)
        session.selectText(UUID())
        #expect(session.selectedClipID == nil)
        session.select(session.timeline.clips[0].id)
        #expect(session.selectedTextID == nil)
    }

    @Test func heldTextEditDoesNotCountAsDragging() throws {
        let session = try makeSession()
        session.beginInteractiveEdit(byDrag: false)
        #expect(session.isEditingInteractively && !session.isDragging)
        session.editText(TextItem(text: "Hi", timelineStart: 0), byDrag: true)
        #expect(session.isDragging)
        session.endDrag()
        #expect(!session.isDragging && session.isEditingInteractively)
    }
}
