import AVFoundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum Thumbnailer {
    enum Failure: Error { case unreadableImage, encodingFailed }

    static let coverMaxPixelSize = 480

    /// Renders a JPEG cover for the clip into the store and returns its file name.
    @concurrent
    static func makeCover(for clip: Clip, in store: MediaStore) async throws -> String {
        let source = store.url(for: clip.mediaFile)
        let image = switch clip.kind {
        case .video: try await videoFrame(of: source, at: clip.sourceStart)
        case .photo: try photoThumbnail(of: source)
        }
        return try store.write(jpegData(from: image), extension: "jpg")
    }

    private static func videoFrame(of url: URL, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: coverMaxPixelSize, height: coverMaxPixelSize)
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private static func photoThumbnail(of url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: coverMaxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw Failure.unreadableImage }
        return image
    }

    private static func jpegData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
