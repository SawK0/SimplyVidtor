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
}
