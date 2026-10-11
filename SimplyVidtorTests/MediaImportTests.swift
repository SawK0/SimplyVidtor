import Foundation
import Testing
@testable import SimplyVidtor

struct MediaImportTests {
    let store = MediaStore.temporary()

    @Test func videoClipReadsDuration() async throws {
        let clip = try await MediaImporter.videoClip(movingIn: TestMedia.sampleVideoCopy(), to: store)
        #expect(clip.kind == .video)
        #expect(abs(clip.sourceDuration - 2) < 0.05)
        #expect(clip.mediaDuration == clip.sourceDuration)
    }

    @Test func unreadableVideoThrows() async throws {
        let bogus = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: bogus)
        await #expect(throws: (any Error).self) {
            try await MediaImporter.videoClip(movingIn: bogus, to: store)
        }
    }

    @Test func photoClipUsesDefaultDuration() throws {
        let clip = try MediaImporter.photoClip(writing: TestMedia.pngData(), extension: "png", to: store)
        #expect(clip.kind == .photo)
        #expect(clip.duration == Clip.defaultPhotoDuration)
        #expect(clip.mediaFile.hasSuffix(".png"))
    }

    @Test func videoCoverIsAJPEGWithinMaxSize() async throws {
        let clip = try await MediaImporter.videoClip(movingIn: TestMedia.sampleVideoCopy(), to: store)
        let cover = try await Thumbnailer.makeCover(for: clip, in: store)
        #expect(cover.hasSuffix(".jpg"))
        let size = try #require(TestMedia.pixelSize(of: store.url(for: cover)))
        #expect(size.width == 160 && size.height == 90)
    }

    @Test func photoCoverIsDownscaled() async throws {
        let clip = try MediaImporter.photoClip(writing: TestMedia.pngData(width: 1200, height: 800), extension: "png", to: store)
        let cover = try await Thumbnailer.makeCover(for: clip, in: store)
        let size = try #require(TestMedia.pixelSize(of: store.url(for: cover)))
        #expect(max(size.width, size.height) == Thumbnailer.coverMaxPixelSize)
    }
}
