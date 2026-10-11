import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Copies picked library items into the media store and turns them into clips.
struct MediaImporter {
    let store: MediaStore

    struct Result {
        var clips: [Clip]
        var failedCount: Int
    }

    /// Imports concurrently but returns clips in selection order.
    func importItems(_ items: [PhotosPickerItem]) async -> Result {
        let clips = await withTaskGroup(of: (Int, Clip?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, try? await importItem(item)) }
            }
            var results = [Clip?](repeating: nil, count: items.count)
            for await (index, clip) in group {
                results[index] = clip
            }
            return results
        }
        let imported = clips.compactMap { $0 }
        return Result(clips: imported, failedCount: items.count - imported.count)
    }

    private func importItem(_ item: PhotosPickerItem) async throws -> Clip {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { throw CocoaError(.fileReadUnknown) }
            return try await Self.videoClip(movingIn: movie.url, to: store)
        }
        guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
        let ext = item.supportedContentTypes.first { $0.conforms(to: .image) }?.preferredFilenameExtension ?? "jpg"
        return try Self.photoClip(writing: data, extension: ext, to: store)
    }

    @concurrent
    nonisolated static func videoClip(movingIn url: URL, to store: MediaStore) async throws -> Clip {
        let file = try store.moveIn(url)
        let duration = try await AVURLAsset(url: store.url(for: file)).load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        return .video(mediaFile: file, duration: duration)
    }

    nonisolated static func photoClip(writing data: Data, extension ext: String, to store: MediaStore) throws -> Clip {
        .photo(mediaFile: try store.write(data, extension: ext))
    }
}

/// A movie handed over by the photo picker, copied out of its temporary location.
private nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
