import SwiftUI

struct ExportSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Export")
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
                    .accessibilityIdentifier("export.close")
            }

            ContentUnavailableView(
                "Export Settings",
                systemImage: "square.and.arrow.up",
                description: Text("Resolution, frame rate and Smart HDR land in M5.")
            )
            .frame(maxHeight: .infinity)

            Button("Export Video") {}
                .buttonStyle(.primary)
                .disabled(true)
        }
        .padding(Theme.Spacing.gutter)
        .foregroundStyle(Theme.Palette.textPrimary)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Palette.bgSurface)
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ExportSheet(onClose: {})
    }
    .preferredColorScheme(.dark)
}
