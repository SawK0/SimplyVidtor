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
    var selectedClipID: Clip.ID?

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let store: MediaStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var pendingSeek: Double?
    /// The timeline before the current drag; set while a trim or reorder is in progress.
    private var interactiveBase: Timeline?

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
        timeline = copy
        if let id = selectedClipID, timeline.index(ofClip: id) == nil { selectedClipID = nil }
        try? project.save(timeline)
        await rebuild()
    }

    var isEditingInteractively: Bool { interactiveBase != nil }

    func select(_ id: Clip.ID?) {
        selectedClipID = (id == selectedClipID) ? nil : id
    }

    // MARK: - Toolbar actions

    var canSplit: Bool { timeline.canSplit(at: currentTime) }

    /// Splits the clip under the playhead and selects the right-hand part.
    func splitAtPlayhead() async {
        var newID: Clip.ID?
        await update { newID = $0.split(at: currentTime) }
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
                timeline.audioItems.append(audio)
            }
        }
        if !clips.isEmpty { await seek(to: timeline.startTime(ofClipAt: index)) }
    }

    // MARK: - Interactive edits

    /// Starts a drag-driven edit. Updates change `timeline` live without saving
    /// or rebuilding; `endInteractiveEdit` commits once.
    func beginInteractiveEdit() {
        guard interactiveBase == nil else { return }
        pause()
        interactiveBase = timeline
    }

    /// Re-applies `edit` to the timeline as it was when the drag began.
    func updateInteractiveEdit(_ edit: (inout Timeline) -> Void) {
        guard var copy = interactiveBase else { return }
        edit(&copy)
        timeline = copy
    }

    func endInteractiveEdit() async {
        guard let base = interactiveBase else { return }
        interactiveBase = nil
        guard timeline != base else { return }
        try? project.save(timeline)
        await rebuild()
    }

    func cancelInteractiveEdit() {
        guard let base = interactiveBase else { return }
        timeline = base
        interactiveBase = nil
    }

    func rebuild() async {
        do {
            let output = try await CompositionBuilder.build(timeline, store: store)
            let item = AVPlayerItem(asset: output.composition)
            item.audioMix = output.audioMix
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
        } else {
            if currentTime >= duration - 0.05 { Task { await seek(to: 0) } }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
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
