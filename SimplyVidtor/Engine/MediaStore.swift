import Foundation
import SwiftUI

/// The folder holding every imported media file and cover image. Projects
/// refer to files by name only, so the folder can move between installs.
nonisolated struct MediaStore: Sendable {
    let directory: URL

    static let standard = MediaStore(
        directory: .applicationSupportDirectory.appending(path: "Media", directoryHint: .isDirectory)
    )

    /// A fresh empty folder, for tests and `-inMemoryStore` runs.
    static func temporary() -> MediaStore {
        MediaStore(directory: .temporaryDirectory.appending(path: "Media-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    func url(for file: String) -> URL {
        directory.appending(path: file, directoryHint: .notDirectory)
    }

    /// Moves `source` into the store under a new unique name.
    func moveIn(_ source: URL) throws -> String {
        try createDirectory()
        let file = uniqueName(extension: source.pathExtension)
        try FileManager.default.moveItem(at: source, to: url(for: file))
        return file
    }

    func write(_ data: Data, extension ext: String) throws -> String {
        try createDirectory()
        let file = uniqueName(extension: ext)
        try data.write(to: url(for: file), options: .atomic)
        return file
    }

    /// Deletes every file whose name is not in `referenced`. Returns how many were removed.
    @discardableResult
    func removeFiles(notIn referenced: Set<String>) throws -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        var removed = 0
        for file in files where !referenced.contains(file) {
            try FileManager.default.removeItem(at: url(for: file))
            removed += 1
        }
        return removed
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func uniqueName(extension ext: String) -> String {
        ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext.lowercased())"
    }
}

extension EnvironmentValues {
    @Entry var mediaStore = MediaStore.standard
}
