import SwiftUI

/// Sits over the preview. Taps select visible text (or toggle playback); the
/// selected text gets a frame and follows drag, pinch and rotate gestures.
struct TextOverlayLayer: View {
    let session: EditorSession

    /// The item as it was when the current gesture began.
    @State private var gestureStart: TextItem?

    var body: some View {
        GeometryReader { geo in
            let video = videoRect(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.clear
                if let item = session.selectedText, item.isVisible(at: session.currentTime) {
                    selectionFrame(for: item, in: video)
                }
            }
            .contentShape(.rect)
            // One gesture so a drag can never also count as a tap.
            .gesture(
                transformGesture(in: video).exclusively(
                    before: SpatialTapGesture().onEnded { tapped(at: $0.location, in: video) }
                )
            )
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - Geometry

    /// Where the rendered frame sits inside the preview (aspect fit).
    private func videoRect(in size: CGSize) -> CGRect {
        let render = session.renderSize
        guard render.width > 0, render.height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale = min(size.width / render.width, size.height / render.height)
        let fitted = CGSize(width: render.width * scale, height: render.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                      width: fitted.width, height: fitted.height)
    }

    /// The item's unrotated box in preview points.
    private func box(for item: TextItem, in video: CGRect) -> CGRect {
        let pixels = TextRenderer.size(for: item, canvas: session.renderSize)
        let scale = video.width / max(session.renderSize.width, 1)
        let size = CGSize(width: pixels.width * scale, height: pixels.height * scale)
        let center = CGPoint(x: video.minX + item.x * video.width, y: video.minY + item.y * video.height)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private func selectionFrame(for item: TextItem, in video: CGRect) -> some View {
        let rect = box(for: item, in: video)
        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.clip / 2)
                    .strokeBorder(Theme.Palette.accent, style: StrokeStyle(lineWidth: Theme.Size.selectionBorder, dash: [6, 4]))
            }
            .accessibilityElement()
            .accessibilityLabel("Selected text")
            .accessibilityValue("\(item.text), \(Int((item.x * 100).rounded()))% across, \(Int((item.y * 100).rounded()))% down")
            .accessibilityIdentifier("preview.textSelection")
            .rotationEffect(.radians(item.rotation))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    // MARK: - Interaction

    private func tapped(at location: CGPoint, in video: CGRect) {
        let hit = session.timeline.textItems.last { item in
            item.isVisible(at: session.currentTime) && box(for: item, in: video).insetBy(dx: -8, dy: -8).contains(location)
        }
        if let hit {
            session.selectText(hit.id)
        } else if session.selectedTextID != nil {
            session.selectText(nil)
        } else {
            session.togglePlayback()
        }
    }

    private func transformGesture(in video: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .simultaneously(with: MagnifyGesture())
            .simultaneously(with: RotateGesture())
            .onChanged { value in
                guard let current = session.selectedText else { return }
                let start = gestureStart ?? current
                gestureStart = start
                var item = start
                if let drag = value.first?.first, video.width > 0, video.height > 0 {
                    item.x = start.x + drag.translation.width / video.width
                    item.y = start.y + drag.translation.height / video.height
                }
                if let magnify = value.first?.second {
                    item.size = start.size * magnify.magnification
                }
                if let rotate = value.second {
                    item.rotation = start.rotation + rotate.rotation.radians
                }
                session.editText(item, byDrag: true)
            }
            .onEnded { _ in
                gestureStart = nil
                session.endDrag()
            }
    }
}
