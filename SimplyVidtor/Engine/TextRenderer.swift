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

    /// `characters` gives each character's motion (index, count) for
    /// per-character animations; offsets are fractions of the canvas's shorter side.
    static func image(for item: TextItem, canvas: CGSize, characters: ((Int, Int) -> MotionState)? = nil) -> CGImage? {
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
        let glyphs = characters.map { state in
            GlyphMotion(text: item.text, unit: min(canvas.width, canvas.height), center: fontSize * 0.35, state: state)
        }
        if item.background == .outline {
            let stroke = attributed(item.text, font: font, color: contrastColor(for: item.color), strokeWidth: 16)
            draw(stroke, in: textRect, context: context, glyphs: glyphs)
        }
        draw(fill, in: textRect, context: context, glyphs: glyphs)
        return context.makeImage()
    }

    /// Per-character motion: maps UTF-16 offsets to character indices.
    private struct GlyphMotion {
        let starts: [Int]
        let unit: CGFloat
        /// Height of a glyph's middle above the baseline.
        let center: CGFloat
        let state: (Int, Int) -> MotionState

        init(text: String, unit: CGFloat, center: CGFloat, state: @escaping (Int, Int) -> MotionState) {
            starts = text.indices.map { $0.utf16Offset(in: text) }
            self.unit = unit
            self.center = center
            self.state = state
        }

        func state(atUTF16 offset: Int) -> MotionState {
            let index = (starts.lastIndex { $0 <= offset }) ?? 0
            return state(index, starts.count)
        }
    }

    private static func draw(_ string: NSAttributedString, in rect: CGRect, context: CGContext, glyphs: GlyphMotion? = nil) {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rect, transform: nil), nil)
        guard let glyphs else {
            CTFrameDraw(frame, context)
            return
        }
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        context.textMatrix = .identity
        for (line, origin) in zip(lines, origins) {
            let lineOrigin = CGPoint(x: rect.minX + origin.x, y: rect.minY + origin.y)
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetPositions(run, CFRange(), &positions)
                CTRunGetAdvances(run, CFRange(), &advances)
                CTRunGetStringIndices(run, CFRange(), &indices)
                for glyph in 0..<count {
                    let state = glyphs.state(atUTF16: indices[glyph])
                    guard state.opacity > 0.001, state.scale > 0 else { continue }
                    let center = CGPoint(x: lineOrigin.x + positions[glyph].x + advances[glyph].width / 2,
                                         y: lineOrigin.y + positions[glyph].y + glyphs.center)
                    context.saveGState()
                    context.setAlpha(state.opacity)
                    // Core Graphics' y axis points up; offsets and rotation are screen-space.
                    context.translateBy(x: center.x + state.offsetX * glyphs.unit, y: center.y - state.offsetY * glyphs.unit)
                    context.rotate(by: -state.rotation)
                    context.scaleBy(x: state.scale, y: state.scale)
                    context.translateBy(x: -center.x, y: -center.y)
                    context.textPosition = lineOrigin
                    CTRunDraw(run, context, CFRange(location: glyph, length: 1))
                    context.restoreGState()
                }
            }
        }
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
