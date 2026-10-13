import AVFoundation
import CoreImage
import VideoToolbox
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import SimplyVidtor

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

    /// The sample video with a 2 s tone as its soundtrack (the bundled sample is silent).
    static func soundVideoCopy() async throws -> URL {
        let video = AVURLAsset(url: try sampleVideoCopy())
        let toneURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: toneURL, seconds: 2)
        let tone = AVURLAsset(url: toneURL)

        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: try await video.load(.duration))
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(range, of: try await video.loadTracks(withMediaType: .video)[0], at: .zero)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audioTrack.insertTimeRange(range, of: try await tone.loadTracks(withMediaType: .audio)[0], at: .zero)

        let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        let output = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try await session.export(to: output, as: .mov)
        return output
    }

    /// A 1 s, 10-bit HLG HEVC clip, like iPhone HDR video.
    static func hdrVideoCopy() async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180,
            AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 180,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let context = CIContext()
        let hlg = CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
        let image = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180))
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            context.render(image, to: buffer!, bounds: image.extent, colorSpace: hlg)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        return url
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

    /// RGB (0...255) of the centre pixel.
    /// Left half red, right half blue.
    static func splitPNGData(width: Int = 200, height: Int = 200) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// Color at a normalized point, origin top left.
    static func color(of image: CGImage, x: Double, y: Double) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let w = CGFloat(image.width), h = CGFloat(image.height)
        context.draw(image, in: CGRect(x: -x * w, y: -(1 - y) * h, width: w, height: h))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    static func centerColor(of image: CGImage) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
