import SwiftUI

/// Adds or edits one text item. The item lives in the session, so preview
/// gestures and timeline drags stay in sync; changes show live and commit as
/// one undo step on Done. An empty text is discarded.
struct TextPanel: View {
    let session: EditorSession
    let onAnimate: () -> Void
    /// Reports when the keyboard opens and closes.
    let onTypingChanged: (Bool) -> Void
    let onDone: () -> Void

    /// The new item before it's first edited onto the timeline.
    @State private var seed: TextItem
    @State private var isNew: Bool
    @FocusState private var isTyping: Bool

    /// Edits `session.selectedText`, or starts a new item with `id` at the playhead.
    init(session: EditorSession, id: TextItem.ID, onAnimate: @escaping () -> Void = {},
         onTypingChanged: @escaping (Bool) -> Void = { _ in }, onDone: @escaping () -> Void) {
        self.session = session
        self.onAnimate = onAnimate
        self.onTypingChanged = onTypingChanged
        self.onDone = onDone
        let existing = session.selectedText
        _isNew = State(initialValue: existing == nil)
        _seed = State(initialValue: existing ?? TextItem(id: id, text: "", timelineStart: session.currentTime))
    }

    /// Looked up by id, not selection: the panel commits after the selection has moved on.
    private var item: TextItem {
        session.timeline.textIndex(of: seed.id).map { session.timeline.textItems[$0] } ?? seed
    }

    /// Reads and writes one field of the item through the session.
    private func binding<Value>(_ keyPath: WritableKeyPath<TextItem, Value>) -> Binding<Value> {
        Binding(
            get: { item[keyPath: keyPath] },
            set: { value in
                var changed = item
                changed[keyPath: keyPath] = value
                session.editText(changed)
            }
        )
    }

    var body: some View {
        ToolPanel(title: isNew ? "Add Text" : "Edit Text", onDone: finish) {
            VStack(spacing: Theme.Spacing.sm) {
                TextField("Enter text", text: binding(\.text))
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
            session.beginInteractiveEdit(byDrag: false)
            if isNew { isTyping = true }
        }
        .onChange(of: isTyping) { _, typing in onTypingChanged(typing) }
        .onDisappear {
            onTypingChanged(false)
            commit()
        }
    }

    private var styleControls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            SegmentedPicker(selection: binding(\.font), options: TextFont.allCases) { font in
                Text("Aa").font(.system(.body, design: Self.design(of: font)).weight(.bold))
            }
            .accessibilityIdentifier("editor.text.font")

            HStack(spacing: 0) {
                ForEach(Array(TextItem.palette.enumerated()), id: \.offset) { index, color in
                    let isSelected = item.color == color
                    Button {
                        binding(\.color).wrappedValue = color
                    } label: {
                        Circle()
                            .fill(Color(TextRenderer.cgColor(color)))
                            .overlay { Circle().strokeBorder(Theme.Palette.separator, lineWidth: Theme.Size.hairline) }
                            .padding(Theme.Spacing.xxs)
                            .overlay {
                                Circle().strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.selectionBorder)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Size.minTapTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(index + 1)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("editor.text.color.\(index)")
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                SegmentedPicker(selection: binding(\.background), options: TextBackground.allCases) { Text(Self.title(of: $0)) }
                    .accessibilityIdentifier("editor.text.background")
                AnimateButton(action: onAnimate)
                    .disabled(isEmpty)
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .foregroundStyle(Theme.Palette.danger)
                .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
                .accessibilityLabel("Delete text")
                .accessibilityIdentifier("editor.text.delete")
            }

            HStack(spacing: Theme.Spacing.xs) {
                TextKeyframeControls(session: session, item: item)
                    .disabled(isEmpty)
                ValueSlider(value: session.sizeBinding(for: item), range: TextItem.sizeRange)
                    .accessibilityLabel("Text size")
                    .accessibilityIdentifier("editor.text.size")
            }
        }
    }

    private var isEmpty: Bool { item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func finish() {
        commit()
        onDone()
    }

    private func delete() {
        binding(\.text).wrappedValue = ""
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
            let id = item.id
            session.updateInteractiveEdit { $0.removeText(id) }
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
