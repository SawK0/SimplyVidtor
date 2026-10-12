import CoreText
import UIKit

/// Draws a `TextItem` into an image with Core Text, so it can be rendered off
/// the main thread by the compositor.
nonisolated enum TextRenderer {
    /// Text wraps at this fraction of the canvas width.
    static let maxWidthFraction = 0.9

    /// Pixel size of `image(for:canvas:)`, without drawing.
    static func size(for item: TextItem, canvas: CGSize) -> CGSize {
        let fontSize = max(item.size * min(canvas.width, canvas.height), 1)
        let padding = (fontSize * 0.3).rounded(.up)
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributed(item.text, font: makeFont(item.font, size: fontSize), color: cgColor(item.color))
        )
        let constraint = CGSize(width: canvas.width * maxWidthFraction, height: .greatestFiniteMagnitude)
        let text = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraint, nil)
        return CGSize(width: (text.width + padding * 2).rounded(.up), height: (text.height + padding * 2).rounded(.up))
    }

    static func image(for item: TextItem, canvas: CGSize) -> CGImage? {
        var item = item
        if item.isSticker { item.background = .none }
        let fontSize = max(item.size * min(canvas.width, canvas.height), 1)
        let font = makeFont(item.font, size: fontSize)
        let padding = (fontSize * 0.3).rounded(.up)
        let color = cgColor(item.color)
        let textColor = item.background == .box ? contrastColor(for: item.color) : color

        let fill = attributed(item.text, font: font, color: textColor)
        let framesetter = CTFramesetterCreateWithAttributedString(fill)
        let constraint = CGSize(width: canvas.width * maxWidthFraction, height: .greatestFiniteMagnitude)
        let textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraint, nil)
        let width = Int((textSize.width + padding * 2).rounded(.up))
        let height = Int((textSize.height + padding * 2).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let textRect = CGRect(x: padding, y: padding, width: textSize.width + 1, height: textSize.height + 1)
        if item.background == .box {
            context.setFillColor(color)
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                                   cornerWidth: fontSize * 0.25, cornerHeight: fontSize * 0.25, transform: nil))
            context.fillPath()
        }
        if item.background == .outline {
            let stroke = attributed(item.text, font: font, color: contrastColor(for: item.color), strokeWidth: 16)
            draw(stroke, in: textRect, context: context)
        }
        draw(fill, in: textRect, context: context)
        return context.makeImage()
    }

    private static func draw(_ string: NSAttributedString, in rect: CGRect, context: CGContext) {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    private static func attributed(_ text: String, font: CTFont, color: CGColor, strokeWidth: Double? = nil) -> NSAttributedString {
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafeBytes(of: &alignment) { bytes in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: bytes.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ]
        if let strokeWidth {
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = strokeWidth
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = color
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    static func makeFont(_ font: TextFont, size: CGFloat) -> CTFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        let design: UIFontDescriptor.SystemDesign = switch font {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size) as CTFont
    }

    static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Black on light colors, white on dark ones.
    static func contrastColor(for rgb: UInt32) -> CGColor {
        let r = Double((rgb >> 16) & 0xFF), g = Double((rgb >> 8) & 0xFF), b = Double(rgb & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance > 0.6 ? cgColor(0x000000) : cgColor(0xFFFFFF)
    }
}

/// Overlays the compositor draws on every frame. The editor updates it while
/// text is being edited so the preview follows without a rebuild.
nonisolated final class OverlayStore: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TextItem]

    init(textItems: [TextItem] = []) {
        items = textItems
    }

    var textItems: [TextItem] {
        get { lock.withLock { items } }
        set { lock.withLock { items = newValue } }
    }
}
