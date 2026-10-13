import Foundation
import ImageIO

/// A set of animations shared as one JSON file. Imported packs are validated
/// before they're stored; projects embed the animations they use.
nonisolated struct MotionPack: Codable, Hashable, Identifiable, Sendable {
    static let formatVersion = 1
    static let maxFileSize = 2_000_000
    static let maxThumbnailSize = 500_000
    static let builtInID = "builtin"

    var formatVersion = Self.formatVersion
    /// Reverse-DNS, e.g. `com.studio.neon`. Animation ids start with it.
    var id: String
    var name: String
    var version: String
    var author: String
    /// PNG or JPEG.
    var thumbnail: Data?
    var animations: [MotionAnimation]

    var isBuiltIn: Bool { id == Self.builtInID }

    static let builtIn = MotionPack(
        id: builtInID, name: "Basics", version: "1", author: "SimplyVidtor", animations: MotionPresets.all
    )

    /// Decodes and validates a pack file.
    static func load(_ data: Data) throws(MotionPackError) -> MotionPack {
        guard data.count <= maxFileSize else { throw .tooLarge }
        // Check the version first, so a newer file says so instead of failing to decode.
        struct Header: Decodable { var formatVersion: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw .unreadable }
        guard header.formatVersion <= formatVersion else { throw .newerFormat }
        let pack: MotionPack
        do {
            pack = try JSONDecoder().decode(MotionPack.self, from: data)
        } catch {
            throw .unreadable
        }
        return try pack.validated()
    }

    /// The pack with keyframes sorted, or the first problem found.
    func validated() throws(MotionPackError) -> MotionPack {
        func check(_ condition: Bool, _ problem: @autoclosure () -> String) throws(MotionPackError) {
            if !condition { throw .invalid(problem()) }
        }
        try check(formatVersion >= 1, "formatVersion must be 1 or more")
        try check(isBuiltIn || id.range(of: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil, "id must be reverse-DNS, like com.studio.pack")
        try check(!name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 40, "name must be 1 to 40 characters")
        try check(!author.trimmingCharacters(in: .whitespaces).isEmpty, "author is missing")
        try check(!version.isEmpty, "version is missing")
        if let thumbnail {
            try check(thumbnail.count <= Self.maxThumbnailSize, "thumbnail is over 500 KB")
            let source = CGImageSourceCreateWithData(thumbnail as CFData, nil)
            try check(source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil, "thumbnail is not an image")
        }
        try check((1...100).contains(animations.count), "a pack holds 1 to 100 animations")
        try check(Set(animations.map(\.id)).count == animations.count, "animation ids must be unique")
        var pack = self
        pack.animations = try animations.map { animation throws(MotionPackError) in
            try validate(animation)
        }
        return pack
    }

    private func validate(_ animation: MotionAnimation) throws(MotionPackError) -> MotionAnimation {
        func check(_ condition: Bool, _ problem: String) throws(MotionPackError) {
            if !condition { throw .invalid("\(animation.id): \(problem)") }
        }
        try check(animation.id.hasPrefix(id + ".") && animation.id.count > id.count + 1, "id must start with the pack id")
        try check(!animation.name.trimmingCharacters(in: .whitespaces).isEmpty && animation.name.count <= 20,
                  "name must be 1 to 20 characters")
        try check(!animation.roles.isEmpty && Set(animation.roles).count == animation.roles.count, "roles must be in, out or loop, once each")
        try check((2...64).contains(animation.keyframes.count), "needs 2 to 64 keyframes")
        try check((0...1).contains(animation.characterSpread), "characterSpread must be 0...1")
        if let duration = animation.defaultDuration {
            try check(AppliedMotion.durationRange.contains(duration), "defaultDuration must be 0.1...3 seconds")
        }
        for frame in animation.keyframes {
            let values = [frame.time, frame.opacity, frame.offsetX, frame.offsetY, frame.scale, frame.rotation, frame.reveal]
            try check(values.allSatisfy(\.isFinite), "values must be numbers")
            try check((0...1).contains(frame.time), "time must be 0...1")
            try check((0...1).contains(frame.opacity) && (0...1).contains(frame.reveal), "opacity and reveal must be 0...1")
            try check((0...10).contains(frame.scale), "scale must be 0...10")
            try check(abs(frame.offsetX) <= 2 && abs(frame.offsetY) <= 2, "offsets must be -2...2")
            try check(abs(frame.rotation) <= 8 * .pi, "rotation must be at most 4 turns")
            try check(frame.easing.isValid, "easing x values must be 0...1")
        }
        var sorted = animation
        sorted.keyframes.sort { $0.time < $1.time }
        try check(sorted.keyframes.first?.time == 0 && sorted.keyframes.last?.time == 1, "keyframes must start at 0 and end at 1")
        if animation.roles.contains(.entrance) || animation.roles.contains(.exit) {
            try check(sorted.state(at: 1).isIdentity, "in and out animations must end at rest")
        }
        if animation.roles.contains(.loop), let first = sorted.keyframes.first?.state, let last = sorted.keyframes.last?.state {
            let turns = (last.rotation - first.rotation) / (2 * .pi)
            var end = last
            end.rotation = first.rotation
            try check(end == first && abs(turns - turns.rounded()) < 1e-6, "loops must end where they start")
        }
        return sorted
    }
}

nonisolated enum MotionPackError: LocalizedError, Equatable {
    case tooLarge, unreadable, newerFormat
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge: String(localized: "The file is larger than 2 MB.")
        case .unreadable: String(localized: "This isn’t a motion pack file.")
        case .newerFormat: String(localized: "This pack needs a newer version of SimplyVidtor.")
        case .invalid(let problem): String(localized: "The pack has a problem: \(problem)")
        }
    }
}
