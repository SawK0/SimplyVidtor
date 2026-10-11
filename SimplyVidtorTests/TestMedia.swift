import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Sample media bundled with the test target, plus generated images.
enum TestMedia {
    private final class BundleToken {}

    /// 2 s, 160×90, H.264, 10 fps.
    static var sampleVideo: URL {
        Bundle(for: BundleToken.self).url(forResource: "sample-2s", withExtension: "mov")!
    }

    /// Copy of the sample video in a temp location, safe to move.
    static func sampleVideoCopy() throws -> URL {
        let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try FileManager.default.copyItem(at: sampleVideo, to: copy)
        return copy
    }

    static func pngData(width: Int = 300, height: Int = 200) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0.8, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
