import SwiftUI

/// Full-screen crop over a still frame of the clip (already rotated).
struct CropEditorView: View {
    let clip: Clip
    let store: MediaStore
    let onCancel: () -> Void
    let onDone: (CropRect) -> Void

    @State private var rect: CropRect
    @State private var ratio: AspectRatio?
    @State private var image: CGImage?
    @State private var dragStart: CropRect?

    private static let fallbackAspect: Double = 1

    init(clip: Clip, store: MediaStore, onCancel: @escaping () -> Void, onDone: @escaping (CropRect) -> Void) {
        self.clip = clip
        self.store = store
        self.onCancel = onCancel
        self.onDone = onDone
        _rect = State(initialValue: clip.crop ?? .full)
    }

    private var imageAspect: Double {
        guard let image, image.height > 0 else { return Self.fallbackAspect }
        return Double(image.width) / Double(image.height)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("crop.cancel")
                Spacer()
                Text("Crop").font(Theme.Typography.headline)
                Spacer()
                Button("Done") { onDone(rect) }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityIdentifier("crop.done")
            }
            .padding(.horizontal, Theme.Spacing.gutter)

            GeometryReader { geo in
                let frame = fittedFrame(in: geo.size)
                cropArea(frame: frame)
            }
            .padding(.horizontal, Theme.Spacing.xl)

            VStack(spacing: Theme.Spacing.sm) {
                SegmentedPicker(selection: ratioBinding, options: [nil] + AspectRatio.allCases.map(Optional.some)) {
                    Text($0?.title ?? String(localized: "Free"))
                }
                .accessibilityIdentifier("crop.ratio")
                Button("Reset") {
                    ratio = nil
                    rect = .full
                }
                .font(Theme.Typography.callout.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .disabled(rect.isFull)
                .accessibilityIdentifier("crop.reset")
            }
            .padding(.horizontal, Theme.Spacing.gutter)
        }
        .padding(.vertical, Theme.Spacing.md)
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Theme.Palette.bgBase)
        .task { await loadFrame() }
    }

    // MARK: - Crop area

    private func cropArea(frame: CGRect) -> some View {
        let box = CGRect(
            x: frame.minX + rect.x * frame.width,
            y: frame.minY + rect.y * frame.height,
            width: rect.width * frame.width,
            height: rect.height * frame.height
        )
        return ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Theme.Palette.bgSurfaceRaised
                }
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)

            // Dim everything outside the crop.
            Path { path in
                path.addRect(frame)
                path.addRect(box)
            }
            .fill(Theme.Palette.scrim, style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            grid(in: box)

            Rectangle()
                .fill(.clear)
                .contentShape(.rect)
                .frame(width: box.width, height: box.height)
                .offset(x: box.minX, y: box.minY)
                .gesture(moveGesture(frame: frame))
                .accessibilityIdentifier("crop.area")

            ForEach(CropRect.Corner.allCases, id: \.self) { corner in
                handle(at: point(of: corner, in: box))
                    .gesture(resizeGesture(corner, frame: frame))
            }
        }
        .coordinateSpace(.named(Self.space))
    }

    private static let space = "cropArea"

    private func grid(in box: CGRect) -> some View {
        Path { path in
            path.addRect(box)
            for third in [1.0 / 3, 2.0 / 3] {
                path.move(to: CGPoint(x: box.minX + box.width * third, y: box.minY))
                path.addLine(to: CGPoint(x: box.minX + box.width * third, y: box.maxY))
                path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * third))
                path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * third))
            }
        }
        .stroke(Theme.Palette.textPrimary.opacity(0.7), lineWidth: Theme.Size.hairline)
        .allowsHitTesting(false)
    }

    private func handle(at point: CGPoint) -> some View {
        Circle()
            .fill(Theme.Palette.accent)
            .frame(width: Theme.Size.trimHandleWidth, height: Theme.Size.trimHandleWidth)
            .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
            .contentShape(.rect)
            .position(point)
    }

    private func point(of corner: CropRect.Corner, in box: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: box.minX, y: box.minY)
        case .topRight: CGPoint(x: box.maxX, y: box.minY)
        case .bottomLeft: CGPoint(x: box.minX, y: box.maxY)
        case .bottomRight: CGPoint(x: box.maxX, y: box.maxY)
        }
    }

    // MARK: - Gestures

    private func moveGesture(frame: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { drag in
                let start = dragStart ?? rect
                dragStart = start
                rect = start.moved(dx: drag.translation.width / frame.width, dy: drag.translation.height / frame.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: CropRect.Corner, frame: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { drag in
                let point = (
                    x: Double((drag.location.x - frame.minX) / frame.width),
                    y: Double((drag.location.y - frame.minY) / frame.height)
                )
                rect = rect.resized(corner, to: point, ratio: ratio.map { $0.value / imageAspect })
            }
    }

    private var ratioBinding: Binding<AspectRatio?> {
        Binding(
            get: { ratio },
            set: { newRatio in
                ratio = newRatio
                if let newRatio { rect = .centered(ratio: newRatio.value, frameAspect: imageAspect) }
            }
        )
    }

    // MARK: - Layout and loading

    /// The frame aspect-fitted and centred in `size`.
    private func fittedFrame(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / imageAspect, size.height)
        let width = scale * imageAspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - scale) / 2, width: width, height: scale)
    }

    private func loadFrame() async {
        let frames = await ThumbnailCache.shared.frames(of: clip, atSourceTimes: [clip.sourceStart], maxPixelSize: 1200, store: store)
        guard let frame = frames.first ?? nil else { return }
        image = await FilterRenderer.rotated(frame, quarterTurns: clip.rotation)
    }
}

#Preview {
    CropEditorView(clip: .video(mediaFile: "missing.mov", duration: 3), store: .temporary(), onCancel: {}, onDone: { _ in })
        .preferredColorScheme(.dark)
}
