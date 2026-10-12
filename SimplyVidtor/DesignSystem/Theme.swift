import SwiftUI

enum Theme {
    enum Palette {
        static let bgBase = Color(hex: 0x0B0B0F)
        static let bgSurface = Color(hex: 0x1C1C22)
        static let bgSurfaceRaised = Color(hex: 0x2A2A33)
        static let separator = Color(hex: 0x3A3A45)

        static let textPrimary = Color(hex: 0xFFFFFF)
        static let textSecondary = Color(hex: 0x9A9AA6)

        static let accent = Color(hex: 0xFFCC00)
        static let onAccent = Color(hex: 0x111111)

        static let trackAudio = Color(hex: 0x30D5C8)
        static let trackText = Color(hex: 0xFF9F0A)
        static let danger = Color(hex: 0xFF453A)

        /// Behind labels drawn over video or thumbnails.
        static let scrim = Color.black.opacity(0.6)
        static let shadow = Color.black.opacity(0.3)
    }

    /// Dynamic Type text styles.
    enum Typography {
        static let display = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.bold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.subheadline
        static let caption = Font.caption.weight(.medium)
        static let timecode = Font.footnote.weight(.semibold).monospacedDigit()
    }

    /// 4-pt scale.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32

        /// Horizontal screen gutter.
        static let gutter: CGFloat = md
    }

    enum Radius {
        static let clip: CGFloat = 8
        static let control: CGFloat = 12
        static let card: CGFloat = 14
        static let button: CGFloat = 16
        static let cardLarge: CGFloat = 22
        static let sheet: CGFloat = 28
    }

    enum Size {
        static let minTapTarget: CGFloat = 44
        static let buttonHeight: CGFloat = 52
        static let compactButtonHeight: CGFloat = 34
        static let circleButton: CGFloat = 40
        static let circleIcon: CGFloat = 16
        static let toolIcon: CGFloat = 22
        static let toolButtonMinWidth: CGFloat = 56
        static let segmentHeight: CGFloat = 36
        static let segmentInset: CGFloat = 3
        static let sliderTrack: CGFloat = 4
        static let sliderThumb: CGFloat = 24
        static let timelineClipHeight: CGFloat = 56
        static let audioTrackHeight: CGFloat = 28
        static let rulerHeight: CGFloat = 28
        static let clipGap: CGFloat = 2
        static let trimHandleWidth: CGFloat = 16
        static let filterSwatch: CGFloat = 56
        static let transitionButton: CGFloat = 24
        static let selectionBorder: CGFloat = 2
        static let playheadWidth: CGFloat = 2
        static let hairline: CGFloat = 1
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
