import Foundation
import Testing
@testable import SimplyVidtor

struct MediaStoreTests {
    let store = MediaStore.temporary()

    private func exists(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: file).path(percentEncoded: false))
    }

    @Test func writeCreatesUniquelyNamedFiles() throws {
        let a = try store.write(Data("a".utf8), extension: "JPG")
        let b = try store.write(Data("b".utf8), extension: "jpg")
        #expect(a != b)
        #expect(a.hasSuffix(".jpg"))
        #expect(try Data(contentsOf: store.url(for: a)) == Data("a".utf8))
    }

    @Test func moveInRemovesTheSource() throws {
        let source = try TestMedia.sampleVideoCopy()
        let file = try store.moveIn(source)
        #expect(file.hasSuffix(".mov"))
        #expect(exists(file))
        #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    }

    @Test func removeFilesKeepsReferencedOnes() throws {
        let keep = try store.write(Data("k".utf8), extension: "mov")
        let drop = try store.write(Data("d".utf8), extension: "mov")
        #expect(try store.removeFiles(notIn: [keep]) == 1)
        #expect(exists(keep))
        #expect(!exists(drop))
    }

    @Test func removeFilesOnMissingFolderIsANoOp() throws {
        #expect(try store.removeFiles(notIn: []) == 0)
    }
}
