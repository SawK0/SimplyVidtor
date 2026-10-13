import SwiftUI
import UniformTypeIdentifiers

/// In, Out and Loop animations for the selected text or sticker. Choosing an
/// animation plays it once in the preview. Commits as one undo step on Done.
struct MotionPanel: View {
    let session: EditorSession
    let onDone: () -> Void

    @State private var role = MotionRole.entrance
    @State private var isImporting = false
    @State private var importError: String?
    @Environment(MotionLibrary.self) private var library: MotionLibrary?

    private var item: TextItem? { session.selectedText }

    var body: some View {
        ToolPanel(title: "Animate", onDone: finish) {
            if let item {
                controls(for: item)
            }
        }
        .onDisappear(perform: commit)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            do {
                try library?.importPack(from: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Couldn’t Import Pack", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func controls(for item: TextItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            SegmentedPicker(selection: $role, options: MotionRole.allCases) { Text(Self.title(of: $0)) }
                .accessibilityIdentifier("editor.motion.role")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    tile(name: String(localized: "None"), isSelected: item.motion[role] == nil) {
                        Image(systemName: "nosign")
                            .font(.system(size: Theme.Size.toolIcon))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } action: {
                        set(nil, on: item)
                    }
                    .accessibilityIdentifier("editor.motion.none")
                    if let applied = item.motion[role],
                       !packs.contains(where: { $0.animations.contains { $0.id == applied.animation.id } }) {
                        // From a removed pack: the project still has it.
                        tile(name: applied.animation.name, isSelected: true) {
                            MotionSample(animation: applied.animation, role: role, text: sampleText(for: item))
                        } action: {}
                        .accessibilityIdentifier("editor.motion.preset.\(applied.animation.id)")
                    }
                    ForEach(packs) { pack in
                        let animations = pack.animations.filter { $0.roles.contains(role) }
                        if !animations.isEmpty {
                            if !pack.isBuiltIn {
                                packLabel(pack)
                            }
                            ForEach(animations) { animation in
                                tile(name: animation.name, isSelected: item.motion[role]?.animation.id == animation.id) {
                                    MotionSample(animation: animation, role: role, text: sampleText(for: item))
                                } action: {
                                    choose(animation, on: item)
                                }
                                .accessibilityIdentifier("editor.motion.preset.\(animation.id)")
                            }
                        }
                    }
                    if library != nil {
                        tile(name: String(localized: "Import"), isSelected: false) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: Theme.Size.toolIcon))
                                .foregroundStyle(Theme.Palette.textSecondary)
                        } action: {
                            isImporting = true
                        }
                        .accessibilityIdentifier("editor.motion.import")
                    }
                }
            }

            if let applied = item.motion[role] {
                settings(for: applied, on: item)
            }
        }
    }

    private var packs: [MotionPack] { library?.packs ?? [.builtIn] }

    private func sampleText(for item: TextItem) -> String {
        item.isSticker ? item.text : "Aa"
    }

    /// Starts an imported pack's tiles; long press to remove the pack.
    private func packLabel(_ pack: MotionPack) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Rectangle()
                .fill(Theme.Palette.separator)
                .frame(width: Theme.Size.hairline, height: Theme.Size.filterSwatch)
            VStack(spacing: Theme.Spacing.xxs) {
                Group {
                    if let data = pack.thumbnail, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "shippingbox")
                            .font(.system(size: Theme.Size.toolIcon))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .frame(width: Theme.Size.filterSwatch / 2, height: Theme.Size.filterSwatch / 2)
                .clipShape(.rect(cornerRadius: Theme.Radius.clip))
                Text(pack.name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: Theme.Size.filterSwatch)
        }
        .contextMenu {
            Button("Remove Pack", systemImage: "trash", role: .destructive) {
                try? library?.remove(pack.id)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pack.name)
        .accessibilityHint("Pack")
        .accessibilityIdentifier("editor.motion.pack.\(pack.id)")
    }

    @ViewBuilder
    private func settings(for applied: AppliedMotion, on item: TextItem) -> some View {
        row("Duration", value: Text(verbatim: applied.duration.formatted(.number.precision(.fractionLength(1))) + "s")) {
            slider(applied, \.duration, range: AppliedMotion.durationRange, on: item)
                .accessibilityIdentifier("editor.motion.duration")
        }
        if applied.animation.hasStrength {
            row("Strength", value: Text(applied.strength, format: .percent.precision(.fractionLength(0)))) {
                slider(applied, \.strength, range: AppliedMotion.strengthRange, origin: 1, on: item)
                    .accessibilityIdentifier("editor.motion.strength")
            }
        }
        HStack(spacing: Theme.Spacing.sm) {
            if applied.animation.isDirectional {
                SegmentedPicker(selection: binding(applied, \.direction, on: item), options: MotionDirection.allCases) {
                    Text(Image(systemName: Self.symbol(of: $0)))
                }
                .accessibilityIdentifier("editor.motion.direction")
            } else {
                Spacer()
            }
            Menu {
                Picker("Easing", selection: binding(applied, \.easing, on: item)) {
                    ForEach(Self.easings, id: \.easing) { option in
                        Text(option.title).tag(option.easing)
                    }
                }
            } label: {
                Label(Self.easings.first { $0.easing == applied.easing }?.title ?? "Custom", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(minHeight: Theme.Size.minTapTarget)
            }
            .accessibilityLabel("Easing")
            .accessibilityIdentifier("editor.motion.easing")
        }
    }

    private func tile(name: String, isSelected: Bool, @ViewBuilder sample: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                sample()
                    .frame(width: Theme.Size.filterSwatch, height: Theme.Size.filterSwatch)
                    .background(Theme.Palette.bgSurfaceRaised, in: .rect(cornerRadius: Theme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.selectionBorder)
                    }
                    .clipShape(.rect(cornerRadius: Theme.Radius.control))
                Text(name)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Theme.Size.filterSwatch)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func row(_ title: LocalizedStringKey, value: Text, @ViewBuilder slider: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.callout)
                .frame(width: Theme.Size.toolButtonMinWidth * 1.2, alignment: .leading)
            slider()
            value
                .font(Theme.Typography.timecode)
                .frame(minWidth: Theme.Size.toolButtonMinWidth, alignment: .trailing)
        }
    }

    private func binding<Value>(_ applied: AppliedMotion, _ keyPath: WritableKeyPath<AppliedMotion, Value>, on item: TextItem) -> Binding<Value> {
        Binding(
            get: { applied[keyPath: keyPath] },
            set: { value in
                var changed = applied
                changed[keyPath: keyPath] = value
                set(changed, on: item, byDrag: session.isDragging)
            }
        )
    }

    private func slider(
        _ applied: AppliedMotion, _ keyPath: WritableKeyPath<AppliedMotion, Double>, range: ClosedRange<Double>,
        origin: Double? = nil, on item: TextItem
    ) -> some View {
        ValueSlider(
            value: binding(applied, keyPath, on: item),
            range: range,
            step: 0.05,
            origin: origin,
            onEditingChanged: { editing in
                if editing {
                    session.beginInteractiveEdit(byDrag: true)
                } else {
                    session.endDrag()
                    previewAnimation()
                }
            }
        )
    }

    // MARK: - Editing

    private func set(_ applied: AppliedMotion?, on item: TextItem, byDrag: Bool = false) {
        var changed = item
        changed.motion[role] = applied
        session.editText(changed, byDrag: byDrag)
    }

    private func choose(_ animation: MotionAnimation, on item: TextItem) {
        var applied = AppliedMotion(animation, role: role)
        // Keep the user's settings when switching between animations.
        if let current = item.motion[role] {
            applied.direction = current.direction
            applied.strength = current.strength
            applied.easing = current.easing
        }
        set(applied, on: item)
        previewAnimation()
    }

    /// Plays the current role's part of the item once.
    private func previewAnimation() {
        guard let item, item.motion[role] != nil else { return }
        let windows = item.motion.windows(duration: item.duration)
        let start = item.timelineStart
        let range: Range<Double> = switch role {
        case .entrance: start..<(start + windows.entrance)
        case .exit: (item.timelineEnd - windows.exit)..<item.timelineEnd
        case .loop: (start + windows.entrance)..<(item.timelineEnd - windows.exit)
        }
        session.playPreview(range)
    }

    private func finish() {
        commit()
        onDone()
    }

    private func commit() {
        guard session.isEditingInteractively else { return }
        Task { await session.endInteractiveEdit() }
    }

    // MARK: - Labels

    static func title(of role: MotionRole) -> LocalizedStringKey {
        switch role {
        case .entrance: "In"
        case .exit: "Out"
        case .loop: "Loop"
        }
    }

    static func symbol(of direction: MotionDirection) -> String {
        switch direction {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }

    static let easings: [(title: LocalizedStringKey, easing: Easing)] = [
        ("Linear", .linear), ("Ease In", .easeIn), ("Ease Out", .easeOut), ("Ease In Out", .easeInOut),
    ]
}

/// A looping sample of an animation on a short text, for the picker tiles.
struct MotionSample: View {
    let animation: MotionAnimation
    let role: MotionRole
    let text: String

    /// The sample plays, then rests before repeating.
    private static let rest = 0.6

    var body: some View {
        let applied = AppliedMotion(animation, role: role)
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let progress = progress(at: context.date.timeIntervalSinceReferenceDate, duration: applied.duration)
            let whole = applied.state(at: progress, role: role)
            GeometryReader { geo in
                let unit = min(geo.size.width, geo.size.height)
                characters(applied, progress: progress, unit: unit)
                    .font(.system(size: unit * 0.32, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .mask { RevealMask(state: whole) }
                    .scaleEffect(whole.scale)
                    .rotationEffect(.radians(whole.rotation))
                    .offset(x: whole.offsetX * unit, y: whole.offsetY * unit)
                    .opacity(whole.opacity)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func progress(at time: Double, duration: Double) -> Double {
        if role == .loop {
            return (time.truncatingRemainder(dividingBy: duration)) / duration
        }
        let cycle = duration + Self.rest
        let t = time.truncatingRemainder(dividingBy: cycle)
        return min(t / duration, 1)
    }

    private func characters(_ applied: AppliedMotion, progress: Double, unit: Double) -> some View {
        let letters = Array(text)
        return HStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                let state = applied.state(at: progress, role: role, character: (index, letters.count))
                Text(String(letter))
                    .scaleEffect(state.scale)
                    .rotationEffect(.radians(state.rotation))
                    .offset(x: state.offsetX * unit, y: state.offsetY * unit)
                    .opacity(state.opacity)
            }
        }
    }
}

/// Shows the part of a view a wipe has revealed.
private struct RevealMask: View {
    let state: MotionState

    var body: some View {
        GeometryReader { geo in
            let r = min(max(state.reveal, 0), 1)
            let size = geo.size
            let rect: CGRect = switch state.revealDirection {
            case .right: CGRect(x: 0, y: 0, width: size.width * r, height: size.height)
            case .left: CGRect(x: size.width * (1 - r), y: 0, width: size.width * r, height: size.height)
            case .up: CGRect(x: 0, y: size.height * (1 - r), width: size.width, height: size.height * r)
            case .down: CGRect(x: 0, y: 0, width: size.width, height: size.height * r)
            }
            Rectangle().frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    return MotionPanel(session: session, onDone: {})
        .preferredColorScheme(.dark)
}

/// Opens the Animate panel from the text and sticker panels.
struct AnimateButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
        }
        .foregroundStyle(Theme.Palette.accent)
        .frame(minWidth: Theme.Size.minTapTarget, minHeight: Theme.Size.minTapTarget)
        .accessibilityLabel("Animate")
        .accessibilityIdentifier("editor.animate")
    }
}
