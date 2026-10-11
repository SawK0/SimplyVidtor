import AVFoundation
import Observation

/// Plays one library item at a time for previewing in the picker.
@Observable
final class AudioPreviewPlayer {
    private(set) var playingID: AudioAsset.ID?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    func toggle(_ id: AudioAsset.ID, url: URL) {
        if playingID == id {
            stop()
        } else {
            play(id, url: url)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playingID = nil
    }

    private func play(_ id: AudioAsset.ID, url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        let player = AVPlayer(playerItem: item)
        player.play()
        self.player = player
        playingID = id
    }
}
