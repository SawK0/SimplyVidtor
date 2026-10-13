import Foundation
import Observation

/// Imported motion packs, one JSON file each in Application Support/Motion.
/// The built-in pack always comes first.
@Observable
final class MotionLibrary {
    let directory: URL
    private(set) var imported: [MotionPack] = []

    static let standardDirectory = URL.applicationSupportDirectory.appending(path: "Motion", directoryHint: .isDirectory)

    init(directory: URL = standardDirectory) {
        self.directory = directory
        reload()
    }

    /// A fresh empty folder, for tests and `-inMemoryStore` runs.
    static func temporary() -> MotionLibrary {
        MotionLibrary(directory: .temporaryDirectory.appending(path: "Motion-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    var packs: [MotionPack] { [.builtIn] + imported }

    func pack(containing animationID: MotionAnimation.ID) -> MotionPack? {
        packs.first { pack in pack.animations.contains { $0.id == animationID } }
    }

    /// Validates and stores the pack at `url`, replacing one with the same id.
    @discardableResult
    func importPack(from url: URL) throws -> MotionPack {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try importPack(MotionPack.load(Data(contentsOf: url)))
    }

    @discardableResult
    func importPack(_ pack: MotionPack) throws -> MotionPack {
        let pack = try pack.validated()
        guard !pack.isBuiltIn else { throw MotionPackError.invalid("builtin is reserved") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(pack).write(to: file(for: pack.id), options: .atomic)
        reload()
        return pack
    }

    /// Projects keep the animations they already use.
    func remove(_ id: MotionPack.ID) throws {
        try FileManager.default.removeItem(at: file(for: id))
        reload()
    }

    private func file(for id: MotionPack.ID) -> URL {
        directory.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    /// Skips files that no longer validate.
    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        imported = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? MotionPack.load(Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
