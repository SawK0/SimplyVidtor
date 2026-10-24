import SwiftUI
import UIKit

/// `UIScrollView` hosting SwiftUI content: horizontal for time, vertical when
/// there are more tracks than fit. SwiftUI's offset-based scroll APIs need
/// iOS 18; this gives exact offsets and native momentum on 17.
struct TimelineScrollView<Content: View>: UIViewRepresentable {
    let contentWidth: CGFloat
    var contentHeight: CGFloat = 0
    /// Applied whenever the user isn't touching the timeline.
    let offset: CGFloat
    var isScrollEnabled = true
    /// Stops touches reaching the content while it's collapsed.
    var isHidden = false
    let onScrub: (CGFloat) -> Void
    let onInteractionChanged: (Bool) -> Void
    /// Long press in content coordinates. Done in UIKit because a SwiftUI long
    /// press inside the hosted content stops the scroll view from panning.
    var onLongPress: (UIGestureRecognizer.State, CGPoint) -> Void = { _, _ in }
    /// Pinch scale since it began, and whether the fingers spread mostly up and down.
    var onPinch: (UIGestureRecognizer.State, _ scale: CGFloat, _ vertical: Bool) -> Void = { _, _, _ in }
    /// False where a touch in content coordinates should drag content instead of scrolling.
    var canScroll: (CGPoint) -> Bool = { _ in true }
    @ViewBuilder let content: Content

    private static var jumpDistance: CGFloat { 40 }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> HostingScrollView<Content> {
        let view = HostingScrollView(rootView: content)
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.decelerationRate = .fast
        view.isDirectionalLockEnabled = true
        view.delegate = context.coordinator
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        // Two fingers pinch; they don't scroll.
        view.panGestureRecognizer.maximumNumberOfTouches = 1
        return view
    }

    func updateUIView(_ view: HostingScrollView<Content>, context: Context) {
        context.coordinator.parent = self
        view.host.rootView = content
        view.canScroll = canScroll
        view.contentWidth = contentWidth
        view.contentHeight = contentHeight
        view.isScrollEnabled = isScrollEnabled
        view.isUserInteractionEnabled = !isHidden
        if !context.coordinator.isInteracting, abs(view.contentOffset.x - offset) > 0.5 {
            // Jumps (ruler taps, undo) glide; playback's small steps don't.
            let isJump = abs(view.contentOffset.x - offset) > Self.jumpDistance
            context.coordinator.isSettingOffset = true
            view.setContentOffset(CGPoint(x: offset, y: view.contentOffset.y), animated: isJump)
            context.coordinator.isSettingOffset = false
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: TimelineScrollView
        var isInteracting = false
        var isSettingOffset = false
        private var pinchIsVertical = false

        init(parent: TimelineScrollView) { self.parent = parent }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isSettingOffset, isInteracting else { return }
            parent.onScrub(scrollView.contentOffset.x)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            setInteracting(true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { setInteracting(false) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            setInteracting(false)
        }

        /// SwiftUI's recognizers in the hosted content (clip taps) would otherwise block the long press.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            parent.onLongPress(recognizer.state, recognizer.location(in: view))
        }

        @objc func pinched(_ recognizer: UIPinchGestureRecognizer) {
            guard let view = recognizer.view else { return }
            if recognizer.state == .began, recognizer.numberOfTouches >= 2 {
                let a = recognizer.location(ofTouch: 0, in: view)
                let b = recognizer.location(ofTouch: 1, in: view)
                // Clearly up and down; anything diagonal zooms time.
                pinchIsVertical = abs(a.y - b.y) > abs(a.x - b.x) * 1.5
            }
            parent.onPinch(recognizer.state, recognizer.scale, pinchIsVertical)
        }

        private func setInteracting(_ value: Bool) {
            guard isInteracting != value else { return }
            isInteracting = value
            parent.onInteractionChanged(value)
        }
    }
}

final class HostingScrollView<Content: View>: UIScrollView {
    let host: UIHostingController<Content>
    var canScroll: (CGPoint) -> Bool = { _ in true }

    var contentWidth: CGFloat = 0 {
        didSet { if contentWidth != oldValue { setNeedsLayout() } }
    }

    var contentHeight: CGFloat = 0 {
        didSet { if contentHeight != oldValue { setNeedsLayout() } }
    }

    init(rootView: Content) {
        host = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        addSubview(host.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Decides from where the touch began: by now the finger has already moved.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === panGestureRecognizer {
            let location = panGestureRecognizer.location(in: self)
            let translation = panGestureRecognizer.translation(in: self)
            if !canScroll(CGPoint(x: location.x - translation.x, y: location.y - translation.y)) { return false }
        }
        return super.gestureRecognizerShouldBegin(recognizer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: max(contentWidth, bounds.width), height: max(contentHeight, bounds.height))
        if contentSize != size { contentSize = size }
        if host.view.frame.size != size { host.view.frame = CGRect(origin: .zero, size: size) }
    }
}
