import AVFoundation
import Foundation
import Testing
@testable import SimplyVidtor

struct ExporterTests {
    let store = MediaStore.temporary()

    @Test func renderSizeScalesShortSideToResolution() {
        var settings = ExportSettings(resolution: .p720)
        #expect(settings.renderSize(for: CGSize(width: 1920, height: 1080)) == CGSize(width: 1280, height: 720))
        #expect(settings.renderSize(for: CGSize(width: 1080, height: 1920)) == CGSize(width: 720, height: 1280))
        settings.resolution = .p2160
        #expect(settings.renderSize(for: CGSize(width: 1080, height: 1080)) == CGSize(width: 2160, height: 2160))
    }

    @Test func estimateGrowsWithResolutionFrameRateAndDuration() {
        let canvas = CGSize(width: 1920, height: 1080)
        let base = ExportSettings()
        let bytes = base.estimatedBytes(duration: 10, canvas: canvas)
        #expect(bytes > 10_000_000 && bytes < 40_000_000, "About 2 MB/s for 1080p30, got \(bytes)")
        #expect(ExportSettings(resolution: .p2160).estimatedBytes(duration: 10, canvas: canvas) > bytes)
        #expect(ExportSettings(frameRate: 60).estimatedBytes(duration: 10, canvas: canvas) > bytes)
        #expect(ExportSettings(usesHEVC: true).estimatedBytes(duration: 10, canvas: canvas) < bytes)
        #expect(base.estimatedBytes(duration: 20, canvas: canvas) > bytes)
    }

    @Test func exportsMovieWithRequestedSizeAndDuration() async throws {
        let clip = Clip.video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
        let progress = ProgressLog()
        let url = try await Exporter.export(
            Timeline(clips: [clip]), store: store, settings: ExportSettings(resolution: .p720, frameRate: 24),
            progress: { progress.record($0) }
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1280, height: 720))
        #expect(abs(try await track.load(.nominalFrameRate) - 24) < 1)
        #expect(progress.last == 1)
    }

    @Test func emptyTimelineFails() async {
        await #expect(throws: Exporter.Failure.self) {
            try await Exporter.export(Timeline(), store: store, settings: ExportSettings())
        }
    }

    @Test func cancellingStopsTheExport() async throws {
        let clip = Clip.video(mediaFile: try store.moveIn(TestMedia.sampleVideoCopy()), duration: 2)
        let timeline = Timeline(clips: Array(repeating: clip, count: 10).map { var c = $0; c.id = UUID(); return c })
        let task = Task { try await Exporter.export(timeline, store: store, settings: ExportSettings(resolution: .p2160)) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
}

/// Collects progress callbacks from the export's background task.
private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}
