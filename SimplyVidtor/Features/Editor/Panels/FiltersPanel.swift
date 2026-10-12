import SwiftUI

/// Filter presets for the selected clip, with intensity and apply to all.
struct FiltersPanel: View {
    let session: EditorSession
    let store: MediaStore
    let onDone: () -> Void

    @State private var source: CGImage?
    @State private var previews: [FilterPreset: CGImage] = [:]

    var body: some View {
        ToolPanel(title: "Filters", onDone: onDone) {
            if let clip = session.selectedClip {
                controls(for: clip)
                    .task(id: PreviewKey(clip: clip)) { await loadPreviews(for: clip) }
            }
        }
    }

    private func controls(for clip: Clip) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    swatch(title: String(localized: "None"), image: source, isSelected: clip.filter == nil) {
                        session.edit { $0.setFilter(nil, ofClip: clip.id) }
                    }
                    .accessibilityIdentifier("editor.filter.none")
                    ForEach(FilterPreset.allCases, id: \.self) { preset in
                        swatch(title: preset.title, image: previews[preset], isSelected: clip.filter?.preset == preset) {
                            let intensity = clip.filter?.intensity ?? 1
                            session.edit { $0.setFilter(ClipFilter(preset: preset, intensity: intensity), ofClip: clip.id) }
                        }
                        .accessibilityIdentifier("editor.filter.\(preset.rawValue)")
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                if let filter = clip.filter {
                    ValueSlider(
                        value: intensityBinding(for: clip, filter: filter),
                        range: 0...1,
                        step: 0.01,
                        onEditingChanged: { editing in
                            if editing {
                                session.beginInteractiveEdit()
                            } else {
                                Task { await session.endInteractiveEdit() }
                            }
                        }
                    )
                    .accessibilityLabel("Intensity")
                    .accessibilityIdentifier("editor.filter.intensity")
                    Text(filter.intensity, format: .percent.precision(.fractionLength(0)))
                        .font(Theme.Typography.timecode)
                        .frame(minWidth: Theme.Size.toolButtonMinWidth, alignment: .trailing)
                } else {
                    Spacer()
                }
                Button("Apply to All") { session.edit { $0.applyFilterToAll(from: clip.id) } }
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accent)
                    .disabled(session.timeline.clips.allSatisfy { $0.filter == clip.filter })
                    .accessibilityIdentifier("editor.filter.applyAll")
            }
            .frame(minHeight: Theme.Size.minTapTarget)
        }
    }

    private func swatch(title: String, image: CGImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                ZStack {
                    Theme.Palette.bgSurfaceRaised
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: Theme.Size.filterSwatch, height: Theme.Size.filterSwatch)
                .clipShape(.rect(cornerRadius: Theme.Radius.clip))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.clip)
                        .strokeBorder(isSelected ? Theme.Palette.accent : .clear, lineWidth: Theme.Size.selectionBorder)
                }
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.textSecondary)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func intensityBinding(for clip: Clip, filter: ClipFilter) -> Binding<Double> {
        Binding(
            get: { filter.intensity },
            set: { intensity in
                session.edit { $0.setFilter(ClipFilter(preset: filter.preset, intensity: intensity), ofClip: clip.id) }
            }
        )
    }

    /// Swatches only depend on the clip's media and first frame.
    private struct PreviewKey: Hashable {
        let mediaFile: String
        let sourceStart: Double

        init(clip: Clip) {
            mediaFile = clip.mediaFile
            sourceStart = clip.sourceStart
        }
    }

    private func loadPreviews(for clip: Clip) async {
        let size = Int(Theme.Size.filterSwatch * 3)
        let frame = await ThumbnailCache.shared.frames(of: clip, atSourceTimes: [clip.sourceStart], maxPixelSize: size, store: store).first ?? nil
        source = frame
        previews = if let frame { await FilterRenderer.previews(of: frame) } else { [:] }
    }
}

#Preview {
    let session = try! EditorSession(project: PreviewData.sampleProjects()[0], store: .temporary())
    session.selectClipAtPlayheadIfNeeded()
    return FiltersPanel(session: session, store: .temporary(), onDone: {})
        .preferredColorScheme(.dark)
}
