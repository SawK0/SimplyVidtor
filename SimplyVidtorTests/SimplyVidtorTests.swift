import Foundation
import Testing
@testable import SimplyVidtor

struct SimplyVidtorTests {
    @Test func appModuleLoads() {
        #expect(Bundle.main.bundleIdentifier != nil)
    }
}
