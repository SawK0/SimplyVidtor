import AVFoundation
import ImageIO

/// Filmstrip frames for timeline clips, cached in memory. Times are rounded
/// to a grid so neighbouring requests share frames.
nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, CGImage>()
    private static let timeGrid = 0.25

    init() {
        cache.countLimit = 600
    }

    /// One frame per source time, `nil` where a frame couldn't be made.
    @concurrent
    func frames(of clip: Clip, atSourceTimes times: [Double], maxPixelSize: Int, store: MediaStore) async -> [CGImage?] {
        let url = store.url(for: clip.mediaFile)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return Array(repeating: nil, count: times.count)
        }
        switch clip.kind {
        case .photo:
            let image = photo(url, maxPixelSize: maxPixelSize)
            return Array(repeating: image, count: times.count)
        case .video:
            return await videoFrames(url, times: times, maxPixelSize: maxPixelSize)
        }
    }

    private func key(_ url: URL, _ time: Double, _ size: Int) -> NSString {
        "\(url.lastPathComponent)@\(time)@\(size)" as NSString
    }

    private func photo(_ url: URL, maxPixelSize: Int) -> CGImage? {
        let key = key(url, 0, maxPixelSize)
        if let cached = cache.object(forKey: key) { return cached }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private func videoFrames(_ url: URL, times: [Double], maxPixelSize: Int) async -> [CGImage?] {
        let snapped = times.map { ($0 / Self.timeGrid).rounded() * Self.timeGrid }
        var results = snapped.map { cache.object(forKey: key(url, $0, maxPixelSize)) }
        let missing = Set(snapped.indices.filter { results[$0] == nil }.map { snapped[$0] })
        guard !missing.isEmpty else { return results }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let tolerance = CMTime(seconds: Self.timeGrid / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let requested = missing.sorted().map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await result in generator.images(for: requested) {
            guard let image = try? result.image else { continue }
            let time = result.requestedTime.seconds
            cache.setObject(image, forKey: key(url, time, maxPixelSize))
            for index in snapped.indices where abs(snapped[index] - time) < 0.001 {
                results[index] = image
            }
        }
        return results
    }
}
