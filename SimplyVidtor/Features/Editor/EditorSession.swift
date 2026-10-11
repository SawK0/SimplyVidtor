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

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private let store: MediaStore
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

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
        try? project.save(timeline)
        await rebuild()
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
