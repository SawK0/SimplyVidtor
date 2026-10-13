import CoreGraphics
import Testing
@testable import SimplyVidtor

struct TextRendererTests {
    private let canvas = CGSize(width: 1080, height: 1920)

    @Test func longerTextIsWiderAndBiggerSizeIsTaller() throws {
        let short = try #require(TextRenderer.image(for: TextItem(text: "Hi", timelineStart: 0), canvas: canvas))
        let long = try #require(TextRenderer.image(for: TextItem(text: "Hello there", timelineStart: 0), canvas: canvas))
        let big = try #require(TextRenderer.image(for: TextItem(text: "Hi", timelineStart: 0, size: 0.2), canvas: canvas))
        #expect(long.width > short.width)
        #expect(big.height > short.height)
    }

    @Test func longTextWrapsInsideTheCanvas() throws {
        let text = String(repeating: "word ", count: 40)
        let image = try #require(TextRenderer.image(for: TextItem(text: text, timelineStart: 0), canvas: canvas))
        #expect(Double(image.width) <= canvas.width)
        #expect(image.height > image.width / 4, "Wrapped onto several lines")
    }

    @Test(arguments: TextFont.allCases)
    func everyFontRenders(font: TextFont) {
        #expect(TextRenderer.image(for: TextItem(text: "Aa", timelineStart: 0, font: font), canvas: canvas) != nil)
    }

    @Test func measuredSizeMatchesImage() throws {
        let item = TextItem(text: "Measure me", timelineStart: 0, background: .box)
        let image = try #require(TextRenderer.image(for: item, canvas: canvas))
        #expect(TextRenderer.size(for: item, canvas: canvas) == CGSize(width: image.width, height: image.height))
    }

    @Test func stickerRendersInColorWithoutBackground() throws {
        var sticker = TextItem.sticker("🔥", at: 0)
        sticker.background = .box
        let image = try #require(TextRenderer.image(for: sticker, canvas: canvas))
        // The corner stays transparent: the box background is ignored for stickers.
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        #expect(pixel[3] == 0)
    }
    /// Alpha summed over the left and right halves.
    private func ink(_ image: CGImage) -> (left: Int, right: Int) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var left = 0, right = 0
        for y in 0..<height {
            for x in 0..<width {
                let alpha = Int(pixels[(y * width + x) * 4 + 3])
                if x < width / 2 { left += alpha } else { right += alpha }
            }
        }
        return (left, right)
    }

    @Test func perCharacterDrawingAtRestMatchesWholeText() throws {
        let item = TextItem(text: "Hello", timelineStart: 0)
        let whole = ink(try #require(TextRenderer.image(for: item, canvas: canvas)))
        let glyphs = ink(try #require(TextRenderer.image(for: item, canvas: canvas) { _, _ in .identity }))
        #expect(abs(glyphs.left - whole.left) < whole.left / 50)
        #expect(abs(glyphs.right - whole.right) < whole.right / 50)
    }

    @Test func typewriterShowsOnlyTheFirstCharacters() throws {
        let item = TextItem(text: "MMMMMM", timelineStart: 0)
        let typed = AppliedMotion(MotionPresets.typewriter, role: .entrance)
        let image = try #require(TextRenderer.image(for: item, canvas: canvas) { index, count in
            typed.state(at: 0.4, role: .entrance, character: (index, count))
        })
        let halves = ink(image)
        #expect(halves.left > 0)
        #expect(halves.right == 0, "Characters past the cursor are hidden")
    }
}
