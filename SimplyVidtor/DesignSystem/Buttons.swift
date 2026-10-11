import SwiftUI

// MARK: - Primary / secondary

/// Full-width filled button. `.primary` for the main action on a screen
/// (Export, Add N clips), `.secondary` for everything else.
struct FilledButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        FilledButtonBody(configuration: configuration, kind: kind)
    }
}

private struct FilledButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FilledButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.buttonHeight)
            .padding(.horizontal, Theme.Spacing.md)
            .background(background, in: .rect(cornerRadius: Theme.Radius.button))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.Palette.onAccent
        case .secondary: Theme.Palette.textPrimary
        case .destructive: Theme.Palette.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.Palette.accent
        case .secondary, .destructive: Theme.Palette.bgSurfaceRaised
        }
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var primary: FilledButtonStyle { FilledButtonStyle(kind: .primary) }
    static var secondary: FilledButtonStyle { FilledButtonStyle(kind: .secondary) }
    static var destructive: FilledButtonStyle { FilledButtonStyle(kind: .destructive) }
}

// MARK: - Circle icon button

/// Round icon-only button used in nav bars and the preview (close, undo, fullscreen).
struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.Size.circleIcon, weight: .semibold))
                .foregroundStyle(isProminent ? Theme.Palette.onAccent : Theme.Palette.textPrimary)
                .frame(width: Theme.Size.circleButton, height: Theme.Size.circleButton)
                .background(
                    isProminent ? Theme.Palette.accent : Theme.Palette.bgSurfaceRaised,
                    in: .circle
                )
                .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
                .contentShape(.circle)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Tool button

/// Icon over label, used in the editor's bottom toolbar (Split, Speed, Volume...).
struct ToolButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .font(.system(size: Theme.Size.toolIcon, weight: .regular))
                    .frame(height: Theme.Size.toolIcon + Theme.Spacing.xxs)
                Text(title)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textPrimary)
            .frame(minWidth: Theme.Size.toolButtonMinWidth, minHeight: Theme.Size.minTapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared press feedback

/// Dims while pressed and when disabled. For buttons that draw their own chrome.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
