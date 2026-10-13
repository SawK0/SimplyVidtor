import AVFoundation

nonisolated struct ExportSettings: Hashable, Sendable {
    enum Resolution: Int, CaseIterable, Sendable {
        case p720 = 720, p1080 = 1080, p2160 = 2160

        var title: String {
            switch self {
            case .p720: "720p"
            case .p1080: "1080p"
            case .p2160: "4K"
            }
        }
    }

    static let frameRates = ProjectFormat.frameRates

    var resolution: Resolution = .p1080
    var frameRate = 30
    /// HEVC instead of H.264: about 40% smaller at the same quality.
    var usesHEVC = false
    /// Keep HDR when the project has HDR clips (10-bit HLG, always HEVC).
    var smartHDR = true

    /// Whether a project with or without HDR clips exports as HDR.
    func exportsHDR(containsHDR: Bool) -> Bool {
        smartHDR && containsHDR
    }

    /// Output size: the canvas scaled so its shorter side matches the
    /// resolution, rounded to even pixels.
    func renderSize(for canvas: CGSize) -> CGSize {
        let short = min(canvas.width, canvas.height)
        guard short > 0 else { return canvas }
        let scale = CGFloat(resolution.rawValue) / short
        let even = { (side: CGFloat) in max(2, (side * scale / 2).rounded() * 2) }
        return CGSize(width: even(canvas.width), height: even(canvas.height))
    }

    /// Rough file size in bytes for `duration` seconds of `canvas`.
    func estimatedBytes(duration: Double, canvas: CGSize, hdr: Bool = false) -> Int64 {
        let size = renderSize(for: canvas)
        // Bits per pixel per frame that high-quality exports land near.
        let bitsPerPixel = hdr ? 0.18 : usesHEVC ? 0.15 : 0.25
        let videoBits = Double(size.width * size.height) * Double(frameRate) * bitsPerPixel
        let audioBits = 128_000.0
        return Int64((videoBits + audioBits) * max(duration, 0) / 8)
    }
}

/// Renders a timeline to a movie file through the same composition and
/// compositor as the preview.
nonisolated enum Exporter {
    enum Failure: LocalizedError {
        case emptyTimeline, unsupported, failed

        var errorDescription: String? {
            switch self {
            case .emptyTimeline: String(localized: "Add a clip before exporting.")
            case .unsupported: String(localized: "This device can’t export with these settings.")
            case .failed: String(localized: "The export didn’t finish.")
            }
        }
    }

    /// Exports to a new file in the temporary folder and returns its URL.
    /// `progress` is called with 0...1; cancelling the task cancels the export.
    /// `forceHDR` is for tests, which have no HDR media.
    @concurrent
    static func export(
        _ timeline: Timeline,
        store: MediaStore,
        settings: ExportSettings,
        forceHDR: Bool = false,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard !timeline.clips.isEmpty else { throw Failure.emptyTimeline }
        let output = try await CompositionBuilder.build(timeline, store: store)
        guard let videoComposition = output.videoComposition.mutableCopy() as? AVMutableVideoComposition else {
            throw Failure.unsupported
        }
        videoComposition.renderSize = settings.renderSize(for: output.videoComposition.renderSize)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.frameRate))

        let hdr = forceHDR || settings.exportsHDR(containsHDR: output.containsHDR)
        if hdr {
            videoComposition.customVideoCompositorClass = HDRVideoCompositor.self
            videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_2020
            videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_2100_HLG
            videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_2020
        }
        let preset = hdr || settings.usesHEVC ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: output.composition, presetName: preset) else {
            throw Failure.unsupported
        }
        session.videoComposition = videoComposition
        session.audioMix = output.audioMix
        let url = URL.temporaryDirectory.appending(path: "SimplyVidtor-\(UUID().uuidString).mp4")

        do {
            try await run(session, to: url, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
        return url
    }

    private static func run(_ session: AVAssetExportSession, to url: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        if #available(iOS 18, *) {
            let watcher = Task {
                for await state in session.states(updateInterval: 0.1) {
                    if case .exporting(let p) = state { progress(p.fractionCompleted) }
                }
            }
            defer { watcher.cancel() }
            try await session.export(to: url, as: .mp4)
        } else {
            session.outputURL = url
            session.outputFileType = .mp4
            let watcher = Task {
                while !Task.isCancelled {
                    progress(Double(session.progress))
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { watcher.cancel() }
            await withTaskCancellationHandler {
                await session.export()
            } onCancel: {
                session.cancelExport()
            }
            try Task.checkCancellation()
            guard session.status == .completed else { throw session.error ?? Failure.failed }
        }
    }
}
