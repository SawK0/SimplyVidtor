import Foundation

/// State the compositor reads on every frame: text overlays and clip looks.
/// The editor updates it during drags so the preview follows without a rebuild.
nonisolated final class LiveStore: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [TextItem]
    private var clipLooks: [Clip.ID: ClipLook]
    private var trackOrder: [Track.ID] = Track.defaults.filter { $0.kind != .audio }.map(\.id)

    init(textItems: [TextItem] = [], looks: [Clip.ID: ClipLook] = [:]) {
        texts = textItems
        clipLooks = looks
    }

    var textItems: [TextItem] {
        get { lock.withLock { texts } }
        set { lock.withLock { texts = newValue } }
    }

    var looks: [Clip.ID: ClipLook] {
        get { lock.withLock { clipLooks } }
        set { lock.withLock { clipLooks = newValue } }
    }

    /// Overlay video and text tracks, bottom to top.
    var visualTrackOrder: [Track.ID] {
        get { lock.withLock { trackOrder } }
        set { lock.withLock { trackOrder = newValue } }
    }

    func look(for id: Clip.ID) -> ClipLook? {
        lock.withLock { clipLooks[id] }
    }

    /// Mirrors the timeline's text and looks.
    func update(from timeline: Timeline) {
        let looks = Dictionary(timeline.allClips.map { ($0.id, $0.look) }, uniquingKeysWith: { first, _ in first })
        let order = timeline.visualTracks.map(\.id)
        lock.withLock {
            texts = timeline.textItems
            clipLooks = looks
            trackOrder = order
        }
    }
}
