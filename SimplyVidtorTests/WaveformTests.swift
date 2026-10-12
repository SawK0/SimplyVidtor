import Foundation
import Testing
@testable import SimplyVidtor

struct WaveformTests {
    @Test func toneHasOnePeakPerFiftiethOfASecond() async throws {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).wav")
        try ToneGenerator.writeTone(to: url, seconds: 2)
        let peaks = await Waveform().peaks(of: url)
        #expect(abs(peaks.count - 2 * Waveform.resolution) <= 2)
        #expect(peaks.allSatisfy { (0...1).contains($0) })
        #expect((peaks.max() ?? 0) > 0.1, "A tone is not silence")
    }

    @Test func unreadableFileHasNoPeaks() async {
        #expect(await Waveform().peaks(of: URL(filePath: "/nonexistent.m4a")).isEmpty)
    }
}
