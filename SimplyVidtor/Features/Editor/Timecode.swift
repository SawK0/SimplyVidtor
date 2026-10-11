import Foundation

nonisolated enum Timecode {
    /// `mm:ss.t`, e.g. `01:05.3`. Tenths are truncated so the display never runs ahead.
    static func string(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded(.down))
        let minutes = tenths / 600
        let secs = (tenths / 10) % 60
        return String(format: "%02d:%02d.%d", minutes, secs, tenths % 10)
    }
}
