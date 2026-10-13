import SwiftUI

/// Previous / add-or-remove / next keyframe buttons, plus the easing out of
/// the keyframe under the playhead.
struct KeyframeControls: View {
    /// Keyframe times on the timeline, sorted.
    let times: [Double]
    let playhead: Double
    /// Off when the playhead isn't on the item.
    let isEnabled: Bool
    let easing: Easing?
    let onToggle: () -> Void
    let onJump: (Double) -> Void
    let onEasing: (Easing) -> Void

    /// Half a frame at 30 fps, so the playhead counts as on a keyframe.
    static let tolerance = 1.0 / 60

    private var isOnKeyframe: Bool { times.contains { abs($0 - playhead) <= Self.tolerance } }
    private var previous: Double? { times.last { $0 < playhead - Self.tolerance } }
    private var next: Double? { times.first { $0 > playhead + Self.tolerance } }

    var body: some View {
        HStack(spacing: 0) {
            button("arrowtriangle.left.fill", label: "Previous keyframe", id: "previous") {
                if let previous { onJump(previous) }
            }
            .disabled(previous == nil)
            button(isOnKeyframe ? "diamond.fill" : "diamond", label: isOnKeyframe ? "Remove keyframe" : "Add keyframe", id: "toggle",
                   action: onToggle)
                .foregroundStyle(isOnKeyframe ? Theme.Palette.accent : Theme.Palette.textPrimary)
                .disabled(!isEnabled)
                .accessibilityAddTraits(isOnKeyframe ? .isSelected : [])
            button("arrowtriangle.right.fill", label: "Next keyframe", id: "next") {
                if let next { onJump(next) }
            }
            .disabled(next == nil)
            if isOnKeyframe, next != nil, let easing {
                Menu {
                    Picker("Easing", selection: Binding(get: { easing }, set: onEasing)) {
                        ForEach(MotionPanel.easings, id: \.easing) { option in
                            Text(option.title).tag(option.easing)
                        }
                    }
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(Theme.Palette.accent)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                }
                .accessibilityLabel("Keyframe easing")
                .accessibilityIdentifier("editor.keyframe.easing")
            }
        }
        .font(Theme.Typography.callout.weight(.semibold))
    }

    private func button(_ symbol: String, label: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("editor.keyframe.\(id)")
    }
}

/// Diamonds marking keyframes along a timeline item.
struct KeyframeMarks: View {
    /// Offsets from the item's start, in points.
    let offsets: [CGFloat]

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(Array(offsets.enumerated()), id: \.offset) { _, x in
                Image(systemName: "diamond.fill")
                    .font(.system(size: Theme.Size.keyframeMark))
                    .foregroundStyle(Theme.Palette.accent)
                    .shadow(color: Theme.Palette.shadow, radius: 1)
                    .offset(x: x - Theme.Size.keyframeMark / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    KeyframeControls(times: [0, 1, 2], playhead: 1, isEnabled: true, easing: .linear,
                     onToggle: {}, onJump: { _ in }, onEasing: { _ in })
        .padding()
        .background(Theme.Palette.bgSurface)
        .preferredColorScheme(.dark)
}
