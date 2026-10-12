import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// What one stretch of the composition draws: a single clip, or two clips
/// blending through a transition.
nonisolated final class ClipInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    enum Content {
        case video(trackID: CMPersistentTrackID, orientation: CGImagePropertyOrientation)
        case photo(URL)
        case blank
    }

    /// One clip's picture and the looks applied to it.
    struct Layer {
        let content: Content
        let filter: ClipFilter?
        let adjustments: ClipAdjustments
        let rotation: Int
        let crop: CropRect?

        init(content: Content, clip: Clip? = nil) {
            self.content = content
            filter = clip?.filter
            adjustments = clip?.adjustments ?? ClipAdjustments()
            rotation = clip?.rotation ?? 0
            crop = clip?.crop
        }
    }

    let timeRange: CMTimeRange
    /// Empty draws black; two layers blend from the first to the second.
    let layers: [Layer]
    let transition: TransitionKind?
    let enablePostProcessing = false
    let containsTweening: Bool
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceTrackIDs: [NSValue]?

    init(timeRange: CMTimeRange, layers: [Layer], transition: TransitionKind? = nil) {
        self.timeRange = timeRange
        self.layers = layers
        self.transition = transition
        containsTweening = transition != nil
        let trackIDs = layers.compactMap { layer -> NSNumber? in
            if case .video(let trackID, _) = layer.content { NSNumber(value: trackID) } else { nil }
        }
        requiredSourceTrackIDs = trackIDs.isEmpty ? nil : trackIDs
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
            context.render(frame(for: request), to: output)
            request.finish(withComposedVideoFrame: output)
        }
    }

    private var black: CIImage {
        CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    private func frame(for request: AVAsynchronousVideoCompositionRequest) -> CIImage {
        guard let instruction = request.videoCompositionInstruction as? ClipInstruction else { return black }
        let canvases = instruction.layers.map { canvas(for: $0, request: request) }
        guard let first = canvases.first else { return black }
        guard let kind = instruction.transition, canvases.count == 2 else { return first }

        let range = instruction.timeRange
        let progress = range.duration.seconds > 0
            ? min(max((request.compositionTime - range.start).seconds / range.duration.seconds, 0), 1)
            : 1
        switch kind {
        case .crossfade:
            return dissolve(first, into: canvases[1], progress)
        case .dipToBlack:
            return progress < 0.5
                ? dissolve(first, into: black, progress * 2)
                : dissolve(black, into: canvases[1], (progress - 0.5) * 2)
        }
    }

    private func dissolve(_ from: CIImage, into to: CIImage, _ progress: Double) -> CIImage {
        let filter = CIFilter.dissolveTransition()
        filter.inputImage = from
        filter.targetImage = to
        filter.time = Float(progress)
        return filter.outputImage?.cropped(to: CGRect(origin: .zero, size: renderSize)) ?? to
    }

    /// One layer, framed, filtered and fitted on black.
    private func canvas(for layer: ClipInstruction.Layer, request: AVAsynchronousVideoCompositionRequest) -> CIImage {
        guard let image = source(for: layer.content, request: request) else { return black }
        let framed = FilterRenderer.framed(image, rotation: layer.rotation, crop: layer.crop)
        let looked = FilterRenderer.apply(layer.adjustments, filter: layer.filter, to: framed)
        return fitted(looked).composited(over: black)
    }

    private func source(for content: ClipInstruction.Content, request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        switch content {
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
