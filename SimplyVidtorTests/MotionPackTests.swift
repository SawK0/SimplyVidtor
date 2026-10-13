import Foundation
import Testing
@testable import SimplyVidtor

struct MotionPackTests {
    private var sampleURL: URL {
        get throws { try #require(Bundle.main.url(forResource: "sample-motion-pack", withExtension: "json")) }
    }

    private func pack(_ animations: [MotionAnimation], id: String = "com.test.pack") -> MotionPack {
        MotionPack(id: id, name: "Test", version: "1", author: "Me", animations: animations)
    }

    private func animation(_ keyframes: [MotionKeyframe], roles: [MotionRole] = [.entrance], id: String = "com.test.pack.a") -> MotionAnimation {
        MotionAnimation(id: id, name: "A", roles: roles, keyframes: keyframes)
    }

    @Test func bundledSampleLoads() throws {
        let pack = try MotionPack.load(Data(contentsOf: sampleURL))
        #expect(pack.id == "com.simplyvidtor.sample")
        #expect(pack.animations.map(\.name) == ["Drop", "Swing", "Heartbeat"])
        #expect(pack.animations[1].keyframes[0].easing == Easing(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1))
    }

    @Test func builtInPackIsValid() throws {
        #expect(throws: Never.self) { try MotionPack.builtIn.validated() }
    }

    @Test func keyframesAreSortedOnLoad() throws {
        let unsorted = pack([animation([MotionKeyframe(time: 1), MotionKeyframe(time: 0, opacity: 0)])])
        let loaded = try MotionPack.load(JSONEncoder().encode(unsorted))
        #expect(loaded.animations[0].keyframes.map(\.time) == [0, 1])
    }

    @Test func newerFormatAndJunkAreRejected() throws {
        var newer = pack([animation([MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)])])
        newer.formatVersion = MotionPack.formatVersion + 1
        #expect(throws: MotionPackError.newerFormat) { try MotionPack.load(JSONEncoder().encode(newer)) }
        #expect(throws: MotionPackError.unreadable) { try MotionPack.load(Data("not json".utf8)) }
        #expect(throws: MotionPackError.tooLarge) { try MotionPack.load(Data(count: MotionPack.maxFileSize + 1)) }
    }

    @Test(arguments: [
        ("bad id", "Pack", [MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)], [MotionRole.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)], [.entrance], "other.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0, opacity: 0)], [.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0.2, opacity: 0), MotionKeyframe(time: 1)], [.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0), MotionKeyframe(time: 1, opacity: 0)], [.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0, scale: 50), MotionKeyframe(time: 1)], [.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0), MotionKeyframe(time: 1, scale: 2)], [.loop], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0, opacity: 0, easing: Easing(x1: 2, y1: 0, x2: 1, y2: 1)), MotionKeyframe(time: 1)], [.entrance], "com.test.pack.a"),
        ("com.test.pack", "Pack", [MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)], [], "com.test.pack.a"),
    ])
    func invalidPacksAreRejected(packID: String, name: String, keyframes: [MotionKeyframe], roles: [MotionRole], animationID: String) {
        let candidate = pack([animation(keyframes, roles: roles, id: animationID)], id: packID)
        #expect(throws: MotionPackError.self) { try candidate.validated() }
    }

    @Test func loopsMayEndWholeTurnsAround() throws {
        let spin = animation([MotionKeyframe(time: 0), MotionKeyframe(time: 1, rotation: 2 * .pi)], roles: [.loop])
        #expect(throws: Never.self) { try pack([spin]).validated() }
    }

    @Test func duplicateAnimationIDsAreRejected() {
        let a = animation([MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)])
        #expect(throws: MotionPackError.self) { try pack([a, a]).validated() }
    }

    @Test func thumbnailMustBeAnImage() {
        var candidate = pack([animation([MotionKeyframe(time: 0, opacity: 0), MotionKeyframe(time: 1)])])
        candidate.thumbnail = Data("nope".utf8)
        #expect(throws: MotionPackError.self) { try candidate.validated() }
        candidate.thumbnail = TestMedia.pngData()
        #expect(throws: Never.self) { try candidate.validated() }
    }

    @Test func libraryImportsReplacesAndRemoves() throws {
        let library = MotionLibrary.temporary()
        #expect(library.packs.map(\.id) == [MotionPack.builtInID])
        try library.importPack(from: sampleURL)
        #expect(library.packs.map(\.id) == [MotionPack.builtInID, "com.simplyvidtor.sample"])
        #expect(library.pack(containing: "com.simplyvidtor.sample.drop")?.name == "Sample Pack")

        var update = try MotionPack.load(Data(contentsOf: sampleURL))
        update.version = "2.0"
        try library.importPack(update)
        #expect(library.imported.count == 1)
        #expect(MotionLibrary(directory: library.directory).imported.first?.version == "2.0", "Persisted")

        try library.remove("com.simplyvidtor.sample")
        #expect(library.imported.isEmpty)
    }

    @Test func builtInIDIsReserved() {
        let library = MotionLibrary.temporary()
        var fake = MotionPack.builtIn
        fake.name = "Fake"
        #expect(throws: (any Error).self) { try library.importPack(fake) }
    }

    @Test func projectsKeepAnimationsAfterThePackIsRemoved() throws {
        let library = MotionLibrary.temporary()
        let pack = try library.importPack(from: sampleURL)
        var item = TextItem(text: "Hi", timelineStart: 0)
        item.motion[.entrance] = AppliedMotion(pack.animations[0], role: .entrance)
        let saved = try JSONEncoder().encode(Timeline(textItems: [item]))
        try library.remove(pack.id)
        let reopened = try JSONDecoder().decode(Timeline.self, from: saved)
        #expect(reopened.textItems[0].motion.entrance?.animation == pack.animations[0])
    }
}
