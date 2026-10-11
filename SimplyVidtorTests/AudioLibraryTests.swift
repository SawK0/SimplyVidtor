import Foundation
import SwiftData
import Testing
@testable import SimplyVidtor

@MainActor
struct AudioLibraryTests {
    private let container: ModelContainer
    private let store = MediaStore.temporary()
    private let library: AudioLibrary

    init() throws {
        container = try AppSchema.container(inMemory: true)
        library = AudioLibrary(context: container.mainContext, store: store)
    }

    private func toneFile(named name: String = "Ocean Waves") throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)/\(name).wav")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ToneGenerator.writeTone(to: url)
        return url
    }

    private func exists(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: file).path(percentEncoded: false))
    }

    @Test func importCopiesFileAndReadsDuration() async throws {
        let source = try toneFile()
        let asset = try await library.importFile(at: source)

        #expect(asset.title == "Ocean Waves")
        #expect(abs(asset.duration - 2) < 0.05)
        #expect(exists(asset.mediaFile))
        #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)), "Source must be copied, not moved")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AudioAsset>()) == 1)
    }

    @Test func importRejectsNonAudio() async throws {
        let bogus = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data("nope".utf8).write(to: bogus)
        await #expect(throws: (any Error).self) { try await library.importFile(at: bogus) }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AudioAsset>()) == 0)
        #expect(try store.removeFiles(notIn: []) == 0, "Failed import must not leave a file behind")
    }

    @Test func extractSavesM4A() async throws {
        let asset = try await library.extractAudio(fromMovieAt: toneFile(), title: "Sound from video")
        #expect(asset.mediaFile.hasSuffix(".m4a"))
        #expect(asset.title == "Sound from video")
        #expect(abs(asset.duration - 2) < 0.1)
    }

    @Test func extractFromSilentVideoFails() async throws {
        await #expect(throws: AudioLibrary.Failure.noAudioTrack) {
            try await library.extractAudio(fromMovieAt: TestMedia.sampleVideo, title: "x")
        }
    }

    @Test func makeItemCoversWholeFile() async throws {
        let asset = try await library.importFile(at: toneFile())
        let item = asset.makeItem()
        #expect(item.mediaFile == asset.mediaFile)
        #expect(item.timelineStart == 0)
        #expect(item.sourceDuration == asset.duration)
    }

    @Test func libraryAudioSurvivesCleanup() async throws {
        let asset = try await library.importFile(at: toneFile())
        try ProjectLibrary(context: container.mainContext, store: store).removeUnusedMedia()
        #expect(exists(asset.mediaFile))
    }

    @Test func deletingAssetKeepsFileUsedByAProject() async throws {
        let asset = try await library.importFile(at: toneFile())
        let projects = ProjectLibrary(context: container.mainContext, store: store)
        try projects.create(timeline: Timeline(audioItems: [asset.makeItem()]))
        let file = asset.mediaFile

        try library.delete(asset)
        #expect(exists(file))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AudioAsset>()) == 0)
    }

    @Test func deletingUnusedAssetRemovesFile() async throws {
        let asset = try await library.importFile(at: toneFile())
        let file = asset.mediaFile
        try library.delete(asset)
        #expect(!exists(file))
    }
}

@MainActor
struct AudioPreviewPlayerTests {
    @Test func togglePlaysThenStops() throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: url)
        let player = AudioPreviewPlayer()
        let a = UUID(), b = UUID()

        player.toggle(a, url: url)
        #expect(player.playingID == a)
        player.toggle(b, url: url)
        #expect(player.playingID == b, "Starting another item switches to it")
        player.toggle(b, url: url)
        #expect(player.playingID == nil)
    }
}
