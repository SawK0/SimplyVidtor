import SwiftUI

// MARK: - Segmented picker

/// Pill-style segmented control.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> Text

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    label(option)
                        .font(Theme.Typography.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.segmentHeight)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Theme.Radius.control - Theme.Size.segmentInset)
                                    .fill(Theme.Palette.accent)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Theme.Size.segmentInset)
        .background(Theme.Palette.bgSurfaceRaised, in: .rect(cornerRadius: Theme.Radius.control))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Toggle

/// System switch tinted with the accent color.
struct AccentSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .tint(Theme.Palette.accent)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
    }
}

extension ToggleStyle where Self == AccentSwitchToggleStyle {
    static var accentSwitch: AccentSwitchToggleStyle { AccentSwitchToggleStyle() }
}

// MARK: - Slider

/// Thin-track slider. The fill starts at `origin` (e.g. 0 for a -1...1 range).
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var origin: Double?
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private let thumb = Theme.Size.sliderThumb

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let x = { (v: Double) in CGFloat(SliderMath.fraction(of: v, in: range)) * usable }
            let valueX = x(value)
            let originX = x(origin ?? range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Palette.separator)
                    .frame(height: Theme.Size.sliderTrack)
                Capsule()
                    .fill(Theme.Palette.accent)
                    .frame(width: abs(valueX - originX), height: Theme.Size.sliderTrack)
                    .offset(x: min(valueX, originX) + thumb / 2)
                Circle()
                    .fill(Theme.Palette.textPrimary)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: Theme.Palette.shadow, radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.15 : 1)
                    .offset(x: valueX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let fraction = (drag.location.x - thumb / 2) / usable
                        value = SliderMath.value(atFraction: fraction, in: range, step: step)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.snappy(duration: 0.15), value: isDragging)
        }
        .frame(height: Theme.Size.minTapTarget)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .number.precision(.fractionLength(0...2))))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = SliderMath.clamp(value + delta, to: range)
            case .decrement: value = SliderMath.clamp(value - delta, to: range)
            @unknown default: break
            }
        }
    }
}

/// Pure value <-> position mapping for `ValueSlider`.
nonisolated enum SliderMath {
    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Position of `value` along the track, 0...1.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clamp(value, to: range) - range.lowerBound) / span
    }

    /// Value at a track position, snapped to `step` from the lower bound.
    static func value(atFraction fraction: Double, in range: ClosedRange<Double>, step: Double? = nil) -> Double {
        let f = min(max(fraction, 0), 1)
        var value = range.lowerBound + f * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            value = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
        }
        return clamp(value, to: range)
    }
}
