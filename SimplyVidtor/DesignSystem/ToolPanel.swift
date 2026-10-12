import SwiftUI

/// Editor tool panel chrome: a title row with a Done button above the controls.
struct ToolPanel<Content: View>: View {
    let title: LocalizedStringKey
    let onDone: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text(title)
                    .font(Theme.Typography.headline)
                Spacer()
                CircleIconButton(systemImage: "checkmark", accessibilityLabel: "Done", isProminent: true, action: onDone)
                    .accessibilityIdentifier("editor.panel.done")
            }
            content
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.bgSurface)
    }
}

#Preview {
    ToolPanel(title: "Speed", onDone: {}) {
        Text("Controls")
    }
    .preferredColorScheme(.dark)
}
