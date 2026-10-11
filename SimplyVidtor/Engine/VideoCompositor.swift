import AVFoundation
import CoreImage

/// What one clip's time range draws.
nonisolated final class ClipInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    enum Content {
        case video(trackID: CMPersistentTrackID, orientation: CGImagePropertyOrientation)
        case photo(URL)
        case blank
    }

    let timeRange: CMTimeRange
    let content: Content
    let enablePostProcessing = false
    let containsTweening = false
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?

    init(timeRange: CMTimeRange, content: Content) {
        self.timeRange = timeRange
        self.content = content
        if case .video(let trackID, _) = content {
            requiredSourceTrackIDs = [NSNumber(value: trackID)]
        } else {
            requiredSourceTrackIDs = nil
        }
    }
}

/// Renders every frame with Core Image, so photos, per-clip orientation and
/// (later) filters, transitions and text share one path for preview and export.
nonisolated final class VideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "VideoCompositor.render")
    private let photos = NSCache<NSURL, CIImage>()
    private var renderSize = CGSize(width: 1080, height: 1920)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        queue.sync { renderSize = newRenderContext.size }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            guard let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: CocoaError(.featureUnsupported))
                return
            }
            let frame = image(for: request).map(fitted) ?? CIImage.empty()
            let canvas = frame.composited(over: CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize)))
            context.render(canvas, to: output)
            request.finish(withComposedVideoFrame: output)
        }
    }

    private func image(for request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        guard let instruction = request.videoCompositionInstruction as? ClipInstruction else { return nil }
        switch instruction.content {
        case .video(let trackID, let orientation):
            return request.sourceFrame(byTrackID: trackID).map { CIImage(cvPixelBuffer: $0).oriented(orientation) }
        case .photo(let url):
            if let cached = photos.object(forKey: url as NSURL) { return cached }
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
            photos.setObject(image, forKey: url as NSURL)
            return image
        case .blank:
            return nil
        }
    }

    /// Aspect-fits `image` inside the render size, centred.
    private func fitted(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = min(renderSize.width / extent.width, renderSize.height / extent.height)
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let x = (renderSize.width - scaled.extent.width) / 2
        let y = (renderSize.height - scaled.extent.height) / 2
        return scaled.transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}

nonisolated extension CGImagePropertyOrientation {
    /// Orientation matching a track's `preferredTransform` (the four right-angle cases).
    init(_ transform: CGAffineTransform) {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): self = .right
        case (0, -1, 1, 0): self = .left
        case (-1, 0, 0, -1): self = .down
        default: self = .up
        }
    }
}
