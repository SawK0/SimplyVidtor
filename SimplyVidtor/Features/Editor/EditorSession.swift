import AVFoundation
import Observation

/// One open project: the timeline being edited and the player previewing it.
@Observable
final class EditorSession {
    let project: Project
    private(set) var timeline: Timeline
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false
    private(set) var buildError: (any Error)?
    /// Pixel size of the rendered frame, for mapping overlays onto the preview.
    private(set) var renderSize = CompositionBuilder.defaultRenderSize
    /// Whether any clip has HDR video, so export can offer Smart HDR.
    private(set) var containsHDR = false
    var selectedClipID: Clip.ID? {
        didSet {
            if selectedClipID != nil {
                selectedTransitionClipID = nil
                selectedTextID = nil
                selectedAudioID = nil
            }
        }
    }
    /// The text being edited; may not be on the timeline yet while it's new.
    private(set) var selectedTextID: TextItem.ID?
    private(set) var selectedAudioID: AudioItem.ID?
    /// The cut after this clip, while editing its transition.
    private(set) var selectedTransitionClipID: Clip.ID?

    @ObservationIgnored let player = AVPlayer()
    /// Lets text and look edits show in the preview without a rebuild.
    @ObservationIgnored private let live = LiveStore()
    @ObservationIgnored private let store: MediaStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeek: Double?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// The timeline before the current drag; set while a trim or reorder is in progress.
    private var interactiveBase: Timeline?
    private var undoStack: [Timeline] = []
    private var redoStack: [Timeline] = []
    static let historyLimit = 50

    var duration: Double { timeline.duration }

    init(project: Project, store: MediaStore) throws {
        self.project = project
        self.store = store
        self.timeline = try project.loadTimeline()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTimeChanged(time.seconds) }
        }
    }

    isolated deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Applies an edit, saves it to the project and refreshes playback.
    func update(_ edit: (inout Timeline) -> Void) async {
        var copy = timeline
        edit(&copy)
        guard copy != timeline else { return }
        let previous = timeline
        timeline = copy
        await commit(replacing: previous)
    }

    // MARK: - History

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() async {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(timeline)
        await apply(previous)
    }

    func redo() async {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(timeline)
        await apply(next)
    }

    /// Records `previous` for undo, then saves and rebuilds the current timeline.
    private func commit(replacing previous: Timeline) async {
        undoStack.append(previous)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        await persistAndRebuild()
    }

    private func apply(_ snapshot: Timeline) async {
        timeline = snapshot
        await persistAndRebuild()
    }

    private func persistAndRebuild() async {
        if let id = selectedClipID, timeline[clip: id] == nil { selectedClipID = nil }
        if let id = selectedAudioID, timeline.audioIndex(of: id) == nil { selectedAudioID = nil }
        if let id = selectedTransitionClipID, !timeline.clips.dropLast().contains(where: { $0.id == id }) {
            selectedTransitionClipID = nil
        }
        try? project.save(timeline)
        await rebuild()
    }

    var isEditingInteractively: Bool { interactiveBase != nil }
    /// A finger is dragging an edit (the timeline stops scrolling). False while
    /// a panel merely holds an edit open, like the text panel.
    private(set) var isDragging = false

    func select(_ id: Clip.ID?) {
        selectedClipID = (id == selectedClipID) ? nil : id
    }

    /// Selects the cut after `id` (or deselects it if already selected).
    func selectTransition(after id: Clip.ID?) {
        let target = id == selectedTransitionClipID ? nil : id
        if target != nil {
            selectedClipID = nil
            selectedTextID = nil
            selectedAudioID = nil
        }
        selectedTransitionClipID = target
    }

    /// Selects a text item, moving the playhead into it so it shows.
    func selectText(_ id: TextItem.ID?) {
        if id != nil {
            selectedClipID = nil
            selectedTransitionClipID = nil
            selectedAudioID = nil
        }
        selectedTextID = id
        if let item = selectedText, !item.isVisible(at: currentTime) {
            Task { await seek(to: item.timelineStart) }
        }
    }

    func selectAudio(_ id: AudioItem.ID?) {
        if id != nil {
            selectedClipID = nil
            selectedTransitionClipID = nil
            selectedTextID = nil
        }
        selectedAudioID = id
    }

    var selectedAudio: AudioItem? {
        guard let id = selectedAudioID, let index = timeline.audioIndex(of: id) else { return nil }
        return timeline.audioItems[index]
    }

    /// Live change to a text item; committed when the text panel finishes.
    /// Drags pass `byDrag` and call `endDrag()` when the finger lifts.
    func editText(_ item: TextItem, byDrag: Bool = false) {
        beginInteractiveEdit(byDrag: byDrag)
        updateInteractiveEdit { $0.upsertText(item) }
    }

    var selectedText: TextItem? {
        guard let id = selectedTextID, let index = timeline.textIndex(of: id) else { return nil }
        return timeline.textItems[index]
    }

    /// The clip whose outgoing transition is selected.
    var transitionClip: Clip? {
        guard let id = selectedTransitionClipID, let index = timeline.index(ofClip: id) else { return nil }
        return timeline.clips[index]
    }

    /// The selected clip's source time at the playhead; `nil` when the playhead is off the clip.
    var selectedClipSourceTime: Double? {
        guard let id = selectedClipID, let clip = timeline[clip: id], let range = timeline.timeRange(ofClip: id) else { return nil }
        let slack = KeyframeControls.tolerance
        guard currentTime >= range.lowerBound - slack, currentTime <= range.upperBound + slack else { return nil }
        return clip.sourceTime(atOffset: min(max(currentTime - range.lowerBound, 0), clip.duration))
    }

    /// Where a clip's source time falls on the timeline.
    func timelineTime(ofClip id: Clip.ID, atSource sourceTime: Double) -> Double? {
        guard let clip = timeline[clip: id], let range = timeline.timeRange(ofClip: id) else { return nil }
        return range.lowerBound + (sourceTime - clip.sourceStart) / clip.speed
    }

    var selectedClip: Clip? {
        guard let id = selectedClipID else { return nil }
        return timeline[clip: id]
    }

    /// Selects the clip under the playhead unless a clip is already selected.
    /// Returns whether a clip is selected afterwards.
    @discardableResult
    func selectClipAtPlayheadIfNeeded() -> Bool {
        if selectedClip == nil, let index = timeline.clipIndex(at: currentTime) {
            selectedClipID = timeline.clips[index].id
        }
        return selectedClip != nil
    }

    /// Applies `edit` live while a drag is in progress, otherwise as a normal edit.
    func edit(_ edit: @escaping (inout Timeline) -> Void) {
        if isEditingInteractively {
            updateInteractiveEdit(edit)
        } else {
            Task { await update(edit) }
        }
    }

    // MARK: - Toolbar actions

    /// A selected overlay splits at the playhead; otherwise the main-track clip under it.
    private var splitTarget: Clip.ID? {
        selectedClipID.flatMap { timeline.isOverlay($0) ? $0 : nil }
    }

    var canSplit: Bool { timeline.canSplit(clip: splitTarget, at: currentTime) }

    /// Splits at the playhead and selects the right-hand part.
    func splitAtPlayhead() async {
        var newID: Clip.ID?
        let target = splitTarget
        let time = currentTime
        await update { timeline in
            newID = target.map { timeline.split(clip: $0, at: time) } ?? timeline.split(at: time)
        }
        if let newID { selectedClipID = newID }
    }

    func duplicateSelected() async {
        guard let id = selectedClipID else { return }
        var copyID: Clip.ID?
        await update { copyID = $0.duplicateClip(id) }
        if let copyID { selectedClipID = copyID }
    }

    func deleteSelected() async {
        guard let id = selectedClipID else { return }
        await update { $0.removeClip(id) }
    }

    /// Inserts clips at the playhead (see `Timeline.insertionIndex`) and moves
    /// the playhead to the first of them. Audio starts at the playhead.
    func insertAtPlayhead(_ clips: [Clip], audio: AudioItem?) async {
        let index = timeline.insertionIndex(at: currentTime)
        let playhead = currentTime
        await update { timeline in
            timeline.insert(clips, at: index)
            if var audio {
                audio.timelineStart = playhead
                timeline.addAudio(audio)
            }
        }
        if !clips.isEmpty { await seek(to: timeline.startTime(ofClipAt: index)) }
    }

    /// Places clips one after another on an overlay track from the playhead, and selects the first.
    func addOverlays(_ clips: [Clip]) async {
        var ids: [Clip.ID] = []
        let playhead = currentTime
        await update { timeline in
            var start = playhead
            for clip in clips {
                ids.append(timeline.insertOverlay(clip, at: start))
                start += clip.duration
            }
        }
        selectedClipID = ids.first
    }

    func addTrack(_ kind: TrackKind) async {
        await update { $0.addTrack(kind) }
    }

    // MARK: - Interactive edits

    /// Starts a drag-driven edit. Updates change `timeline` live without saving
    /// or rebuilding; `endInteractiveEdit` commits once.
    func beginInteractiveEdit(byDrag: Bool = true) {
        if byDrag { isDragging = true }
        guard interactiveBase == nil else { return }
        pause()
        interactiveBase = timeline
    }

    /// Re-applies `edit` to the timeline as it was when the drag began.
    func updateInteractiveEdit(_ edit: (inout Timeline) -> Void) {
        guard var copy = interactiveBase else { return }
        edit(&copy)
        let changed = Self.drawsDifferently(copy, timeline)
        timeline = copy
        if changed { showLiveChanges() }
    }

    /// Whether text or clip looks differ, which the live store can show without a rebuild.
    private static func drawsDifferently(_ a: Timeline, _ b: Timeline) -> Bool {
        a.textItems != b.textItems || a.allClips.map(\.look) != b.allClips.map(\.look)
    }

    /// Pushes text and looks to the compositor and redraws the current frame.
    private func showLiveChanges() {
        live.update(from: timeline)
        guard let item = player.currentItem, let composition = item.videoComposition else { return }
        item.videoComposition = composition.mutableCopy() as? AVVideoComposition
    }

    /// Ends a drag inside an edit a panel keeps open; the panel commits later.
    func endDrag() {
        isDragging = false
    }

    func endInteractiveEdit() async {
        isDragging = false
        guard let base = interactiveBase else { return }
        interactiveBase = nil
        guard timeline != base else { return }
        await commit(replacing: base)
    }

    func cancelInteractiveEdit() {
        isDragging = false
        guard let base = interactiveBase else { return }
        let changed = Self.drawsDifferently(base, timeline)
        timeline = base
        interactiveBase = nil
        if changed { showLiveChanges() }
    }

    func rebuild() async {
        do {
            let output = try await CompositionBuilder.build(timeline, store: store, live: live)
            let item = AVPlayerItem(asset: output.composition)
            item.audioMix = output.audioMix
            item.videoComposition = output.videoComposition
            renderSize = output.videoComposition.renderSize
            containsHDR = output.containsHDR
            observeEnd(of: item)
            player.replaceCurrentItem(with: item)
            buildError = nil
            await seek(to: min(currentTime, duration))
        } catch {
            buildError = error
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else if currentTime >= duration - 0.05 {
            // Rewind first: playing before the seek lands just hits the end again.
            isPlaying = true
            Task {
                await seek(to: 0)
                guard isPlaying else { return }
                player.play()
            }
        } else {
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        previewTask?.cancel()
        player.pause()
        isPlaying = false
    }

    /// Plays `range` once, e.g. to show an animation after choosing it.
    func playPreview(_ range: Range<Double>) {
        pause()
        guard range.upperBound > range.lowerBound else { return }
        previewTask = Task {
            await seek(to: range.lowerBound)
            guard !Task.isCancelled else { return }
            player.play()
            isPlaying = true
            try? await Task.sleep(for: .seconds(range.upperBound - range.lowerBound))
            guard !Task.isCancelled, isPlaying else { return }
            player.pause()
            isPlaying = false
            // Rest just inside the range, so the item is still visible.
            await seek(to: max(range.upperBound - 0.02, range.lowerBound))
        }
    }

    func seek(to seconds: Double) async {
        let target = min(max(seconds, 0), duration)
        currentTime = target
        await player.seek(to: CompositionBuilder.time(target), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// For continuous scrubbing: updates the time immediately and keeps only
    /// one seek in flight, jumping to the latest target when it lands.
    func scrub(to seconds: Double) {
        let target = min(max(seconds, 0), duration)
        currentTime = target
        pendingSeek = target
        if !isSeeking { seekToPending() }
    }

    private func seekToPending() {
        guard let target = pendingSeek else {
            isSeeking = false
            return
        }
        pendingSeek = nil
        isSeeking = true
        Task {
            await player.seek(to: CompositionBuilder.time(target), toleranceBefore: .zero, toleranceAfter: .zero)
            seekToPending()
        }
    }

    private func playerTimeChanged(_ seconds: Double) {
        guard seconds.isFinite, isPlaying else { return }
        currentTime = min(seconds, duration)
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }
}
