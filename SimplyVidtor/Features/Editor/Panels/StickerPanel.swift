import SwiftUI

/// Emoji stickers. Tapping an emoji adds a sticker at the playhead, or swaps
/// the selected one. Everything commits as one undo step on Done.
struct StickerPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    private let columns = [GridItem(.adaptive(minimum: Theme.Size.minTapTarget), spacing: Theme.Spacing.xxs)]

    private var sticker: TextItem? {
        session.selectedText.flatMap { $0.isSticker ? $0 : nil }
    }

    var body: some View {
        ToolPanel(title: "Stickers", onDone: finish) {
            VStack(spacing: Theme.Spacing.sm) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.xxs) {
                        ForEach(Array(TextItem.stickers.enumerated()), id: \.offset) { index, emoji in
                            Button { choose(emoji) } label: {
                                Text(emoji)
                                    .font(.system(size: Theme.Size.toolIcon * 1.4))
                                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                                    .background(sticker?.text == emoji ? Theme.Palette.bgSurfaceRaised : .clear,
                                                in: .rect(cornerRadius: Theme.Radius.control))
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityIdentifier("editor.sticker.\(index)")
                        }
                    }
                }
                .frame(maxHeight: Theme.Size.minTapTarget * 2.5)

                if let sticker {
                    HStack(spacing: Theme.Spacing.sm) {
                        ValueSlider(value: sizeBinding(for: sticker), range: TextItem.sizeRange)
                            .accessibilityLabel("Sticker size")
                            .accessibilityIdentifier("editor.sticker.size")
                        Button(role: .destructive) { delete(sticker) } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(Theme.Palette.danger)
                        .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
                        .accessibilityLabel("Delete sticker")
                        .accessibilityIdentifier("editor.sticker.delete")
                    }
                }
            }
        }
        .onAppear { session.beginInteractiveEdit(byDrag: false) }
        .onDisappear(perform: commit)
    }

    private func choose(_ emoji: String) {
        if var sticker {
            sticker.text = emoji
            session.editText(sticker)
        } else {
            let new = TextItem.sticker(emoji, at: session.currentTime)
            session.editText(new)
            session.selectText(new.id)
        }
    }

    private func sizeBinding(for sticker: TextItem) -> Binding<Double> {
        Binding(
            get: { sticker.size },
            set: { size in
                var changed = sticker
                changed.size = size
                session.editText(changed)
            }
        )
    }

    private func delete(_ sticker: TextItem) {
        session.updateInteractiveEdit { $0.removeText(sticker.id) }
        session.selectText(nil)
    }

    private func finish() {
        commit()
        onDone()
    }

    private func commit() {
        guard session.isEditingInteractively else { return }
        Task { await session.endInteractiveEdit() }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return StickerPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}
