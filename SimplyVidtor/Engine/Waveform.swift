import AVFoundation

/// Loudness peaks of audio files for drawing waveforms, cached per file.
nonisolated final class Waveform: @unchecked Sendable {
    static let shared = Waveform()
    /// Peaks per second of audio.
    static let resolution = 50
    private static let sampleRate = 8000

    private let cache = NSCache<NSURL, NSArray>()

    /// One peak (0...1) per `1 / resolution` seconds; empty if unreadable.
    @concurrent
    func peaks(of url: URL) async -> [Float] {
        if let cached = cache.object(forKey: url as NSURL) as? [Float] { return cached }
        let peaks = (try? await Self.read(url)) ?? []
        if !peaks.isEmpty { cache.setObject(peaks as NSArray, forKey: url as NSURL) }
        return peaks
    }

    private static func read(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        // Mono 16-bit at a low rate: plenty for peaks and quick to read.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }

        let bucketSize = sampleRate / resolution
        var peaks: [Float] = []
        var peak: Int32 = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &samples)
            for sample in samples {
                peak = max(peak, abs(Int32(sample)))
                count += 1
                if count == bucketSize {
                    peaks.append(Float(peak) / Float(Int16.max))
                    peak = 0
                    count = 0
                }
            }
        }
        if count > 0 { peaks.append(Float(peak) / Float(Int16.max)) }
        return peaks
    }
}
