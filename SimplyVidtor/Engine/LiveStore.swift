import Foundation

/// State the compositor reads on every frame: text overlays and clip looks.
/// The editor updates it during drags so the preview follows without a rebuild.
nonisolated final class LiveStore: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [TextItem]
    private var clipLooks: [Clip.ID: ClipLook]

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

    func look(for id: Clip.ID) -> ClipLook? {
        lock.withLock { clipLooks[id] }
    }

    /// Mirrors the timeline's text and looks.
    func update(from timeline: Timeline) {
        let looks = Dictionary(timeline.clips.map { ($0.id, $0.look) }, uniquingKeysWith: { first, _ in first })
        lock.withLock {
            texts = timeline.textItems
            clipLooks = looks
        }
    }
}
