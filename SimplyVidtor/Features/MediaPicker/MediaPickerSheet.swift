import SwiftUI

enum MediaPickerTab: String, CaseIterable, Identifiable {
    case media, audio
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .media: "Videos & Photos"
        case .audio: "Audio"
        }
    }
}

struct MediaPickerSheet: View {
    @State var tab: MediaPickerTab
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Add Media")
                    .font(Theme.Typography.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onCancel)
                    .accessibilityIdentifier("mediaPicker.close")
            }

            SegmentedPicker(selection: $tab, options: MediaPickerTab.allCases) { Text($0.title) }

            ContentUnavailableView {
                Label(tab.title, systemImage: tab == .media ? "photo.on.rectangle" : "music.note.list")
            } description: {
                switch tab {
                case .media: Text("The photo library picker lands in M1.")
                case .audio: Text("Imported audio with preview lands in M1.")
                }
            }
            .frame(maxHeight: .infinity)

            Button("Add", action: onAdd)
                .buttonStyle(.primary)
                .accessibilityIdentifier("mediaPicker.add")
        }
        .padding(Theme.Spacing.gutter)
        .foregroundStyle(Theme.Palette.textPrimary)
        .presentationBackground(Theme.Palette.bgSurface)
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        MediaPickerSheet(tab: .media, onCancel: {}, onAdd: {})
    }
    .preferredColorScheme(.dark)
}
