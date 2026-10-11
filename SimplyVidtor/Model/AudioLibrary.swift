import AVFoundation
import Foundation
import SwiftData

/// Imports audio into the library from Files or from a video's soundtrack.
struct AudioLibrary {
    enum Failure: LocalizedError {
        case noAudioTrack, exportFailed

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: String(localized: "This video has no sound.")
            case .exportFailed: String(localized: "The audio couldn’t be extracted.")
            }
        }
    }

    let context: ModelContext
    let store: MediaStore

    /// Copies a file picked in Files (security-scoped) into the store.
    @discardableResult
    func importFile(at url: URL) async throws -> AudioAsset {
        let file = try await Self.copyIn(url, to: store)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return try await insert(file: file, fallbackTitle: fallbackTitle)
    }

    /// Saves the soundtrack of the movie at `url` as an M4A.
    @discardableResult
    func extractAudio(fromMovieAt url: URL, title: String) async throws -> AudioAsset {
        let file = try await Self.exportAudio(of: url, to: store)
        return try await insert(file: file, fallbackTitle: title)
    }

    func delete(_ asset: AudioAsset) throws {
        context.delete(asset)
        try context.save()
        try ProjectLibrary(context: context, store: store).removeUnusedMedia()
    }

    /// Removes the copied file if it turns out not to be playable audio.
    private func insert(file: String, fallbackTitle: String) async throws -> AudioAsset {
        let asset = AVURLAsset(url: store.url(for: file))
        let duration: Double
        do {
            duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            try? FileManager.default.removeItem(at: store.url(for: file))
            throw error
        }
        let title = await Self.metadataTitle(of: asset) ?? fallbackTitle
        let audio = AudioAsset(title: title, mediaFile: file, duration: duration)
        context.insert(audio)
        try context.save()
        return audio
    }

    @concurrent
    private nonisolated static func copyIn(_ url: URL, to store: MediaStore) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let temp = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(url.pathExtension)")
        try FileManager.default.copyItem(at: url, to: temp)
        return try store.moveIn(temp)
    }

    @concurrent
    private nonisolated static func exportAudio(of url: URL, to store: MediaStore) async throws -> String {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw Failure.noAudioTrack }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.exportFailed
        }
        let output = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        if #available(iOS 18, *) {
            try await session.export(to: output, as: .m4a)
        } else {
            session.outputURL = output
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else { throw session.error ?? Failure.exportFailed }
        }
        return try store.moveIn(output)
    }

    @concurrent
    private nonisolated static func metadataTitle(of asset: AVURLAsset) async -> String? {
        guard let items = try? await asset.load(.commonMetadata),
              let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierTitle).first,
              let title = try? await item.load(.stringValue),
              !title.isEmpty
        else { return nil }
        return title
    }
}
