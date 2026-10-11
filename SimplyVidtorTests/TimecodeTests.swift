import Testing
@testable import SimplyVidtor

struct TimecodeTests {
    @Test(arguments: [
        (0.0, "00:00.0"),
        (5.0, "00:05.0"),
        (12.46, "00:12.4"),
        (65.3, "01:05.3"),
        (600.0, "10:00.0"),
        (-1.0, "00:00.0"),
    ])
    func formats(seconds: Double, expected: String) {
        #expect(Timecode.string(seconds) == expected)
    }
}
