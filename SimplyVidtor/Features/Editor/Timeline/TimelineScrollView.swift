import SwiftUI
import UIKit

/// Horizontal `UIScrollView` hosting SwiftUI content. SwiftUI's offset-based
/// scroll APIs need iOS 18; this gives exact offsets and native momentum on 17.
struct TimelineScrollView<Content: View>: UIViewRepresentable {
    let contentWidth: CGFloat
    /// Applied whenever the user isn't touching the timeline.
    let offset: CGFloat
    var isScrollEnabled = true
    let onScrub: (CGFloat) -> Void
    let onInteractionChanged: (Bool) -> Void
    /// Long press in content coordinates. Done in UIKit because a SwiftUI long
    /// press inside the hosted content stops the scroll view from panning.
    var onLongPress: (UIGestureRecognizer.State, CGFloat) -> Void = { _, _ in }
    @ViewBuilder let content: Content

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> HostingScrollView<Content> {
        let view = HostingScrollView(rootView: content)
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.decelerationRate = .fast
        view.delegate = context.coordinator
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ view: HostingScrollView<Content>, context: Context) {
        context.coordinator.parent = self
        view.host.rootView = content
        view.contentWidth = contentWidth
        view.isScrollEnabled = isScrollEnabled
        if !context.coordinator.isInteracting, abs(view.contentOffset.x - offset) > 0.5 {
            context.coordinator.isSettingOffset = true
            view.contentOffset.x = offset
            context.coordinator.isSettingOffset = false
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: TimelineScrollView
        var isInteracting = false
        var isSettingOffset = false

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
            parent.onLongPress(recognizer.state, recognizer.location(in: view).x)
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

    var contentWidth: CGFloat = 0 {
        didSet { if contentWidth != oldValue { setNeedsLayout() } }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: max(contentWidth, bounds.width), height: bounds.height)
        if contentSize != size { contentSize = size }
        if host.view.frame.size != size { host.view.frame = CGRect(origin: .zero, size: size) }
    }
}
