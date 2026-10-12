import SwiftUI

/// Adds or edits one text item. Changes show live and commit as one undo step
/// on Done; an empty text is discarded.
struct TextPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    @State private var draft: TextItem
    /// Kept in state: once the draft is on the timeline, a re-created panel would think it existed before.
    @State private var isNew: Bool
    @FocusState private var isTyping: Bool

    /// Edits `session.selectedText`, or starts a new item with `id` at the playhead.
    init(session: EditorSession, id: TextItem.ID, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        let existing = session.selectedText
        _isNew = State(initialValue: existing == nil)
        _draft = State(initialValue: existing ?? TextItem(id: id, text: "", timelineStart: session.currentTime))
    }

    var body: some View {
        ToolPanel(title: isNew ? "Add Text" : "Edit Text", onDone: finish) {
            VStack(spacing: Theme.Spacing.sm) {
                TextField("Enter text", text: $draft.text)
                    .focused($isTyping)
                    .submitLabel(.done)
                    .onSubmit { isTyping = false }
                    .font(Theme.Typography.body)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .frame(minHeight: Theme.Size.minTapTarget)
                    .background(Theme.Palette.bgSurfaceRaised, in: .rect(cornerRadius: Theme.Radius.control))
                    .accessibilityIdentifier("editor.text.field")
                if !isTyping {
                    styleControls
                }
            }
        }
        .onAppear {
            session.beginInteractiveEdit()
            if isNew { isTyping = true }
        }
        .onDisappear(perform: commit)
        .onChange(of: draft) { _, item in
            session.updateInteractiveEdit { $0.upsertText(item) }
        }
    }

    private var styleControls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SegmentedPicker(selection: $draft.font, options: TextFont.allCases) { font in
                Text("Aa").font(.system(.body, design: Self.design(of: font)).weight(.bold))
            }
            .accessibilityIdentifier("editor.text.font")

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(TextItem.palette.enumerated()), id: \.offset) { index, color in
                    let isSelected = draft.color == color
                    Button {
                        draft.color = color
                    } label: {
                        Circle()
                            .fill(Color(TextRenderer.cgColor(color)))
                            .overlay { Circle().strokeBorder(Theme.Palette.separator, lineWidth: Theme.Size.hairline) }
                            .padding(Theme.Spacing.xxs)
                            .overlay {
                                Circle().strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.selectionBorder)
                            }
                            .frame(maxWidth: Theme.Size.minTapTarget, maxHeight: Theme.Size.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(index + 1)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("editor.text.color.\(index)")
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                SegmentedPicker(selection: $draft.background, options: TextBackground.allCases) { Text(Self.title(of: $0)) }
                    .accessibilityIdentifier("editor.text.background")
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Theme.Palette.danger)
                .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
                .accessibilityLabel("Delete text")
                .accessibilityIdentifier("editor.text.delete")
            }

            ValueSlider(value: $draft.size, range: TextItem.sizeRange)
                .accessibilityLabel("Text size")
                .accessibilityIdentifier("editor.text.size")
        }
    }

    private var isEmpty: Bool { draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func finish() {
        commit()
        onDone()
    }

    private func delete() {
        draft.text = ""
        finish()
    }

    /// Runs once: the first of Done, Delete or the panel going away.
    private func commit() {
        guard session.isEditingInteractively else { return }
        if isEmpty {
            if isNew {
                session.cancelInteractiveEdit()
                return
            }
            session.updateInteractiveEdit { $0.removeText(draft.id) }
        }
        Task { await session.endInteractiveEdit() }
    }

    static func design(of font: TextFont) -> Font.Design {
        switch font {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    static func title(of background: TextBackground) -> LocalizedStringKey {
        switch background {
        case .none: "Plain"
        case .box: "Box"
        case .outline: "Outline"
        }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return TextPanel(session: session, id: UUID(), onDone: {})
        .preferredColorScheme(.dark)
}
