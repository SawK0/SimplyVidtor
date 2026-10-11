import Foundation
import SwiftData

/// An audio file in the app-wide library, reusable across projects.
@Model
final class AudioAsset {
    @Attribute(.unique) var id: UUID
    var title: String
    /// File name inside the media store.
    var mediaFile: String
    var duration: Double
    var importedAt: Date

    init(title: String, mediaFile: String, duration: Double, importedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.mediaFile = mediaFile
        self.duration = duration
        self.importedAt = importedAt
    }

    func makeItem() -> AudioItem {
        AudioItem(mediaFile: mediaFile, mediaDuration: duration)
    }
}
