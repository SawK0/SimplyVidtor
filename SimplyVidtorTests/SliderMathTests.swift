import Testing
@testable import SimplyVidtor

struct SliderMathTests {
    @Test func fractionMapsRangeToUnitInterval() {
        #expect(SliderMath.fraction(of: 0.1, in: 0.1...10) == 0)
        #expect(SliderMath.fraction(of: 10, in: 0.1...10) == 1)
        #expect(SliderMath.fraction(of: 0, in: -1...1) == 0.5)
    }

    @Test func fractionClampsOutOfRangeValues() {
        #expect(SliderMath.fraction(of: -5, in: 0...1) == 0)
        #expect(SliderMath.fraction(of: 5, in: 0...1) == 1)
    }

    @Test func fractionOfEmptyRangeIsZero() {
        #expect(SliderMath.fraction(of: 3, in: 3...3) == 0)
    }

    @Test func valueAtFractionIsInverseOfFraction() {
        #expect(SliderMath.value(atFraction: 0.5, in: -1...1) == 0)
        #expect(SliderMath.value(atFraction: 0.25, in: 0...100) == 25)
    }

    @Test func valueAtFractionClampsDragsPastTheEnds() {
        #expect(SliderMath.value(atFraction: -0.3, in: 0...10) == 0)
        #expect(SliderMath.value(atFraction: 1.7, in: 0...10) == 10)
    }

    @Test func valueSnapsToStepCountedFromLowerBound() {
        // 0.1...10 in 0.1 steps: 0.5 of the track is 5.05, snaps to 5.0 or 5.1
        let snapped = SliderMath.value(atFraction: 0.5, in: 0.1...10, step: 0.1)
        let steps = (snapped - 0.1) / 0.1
        #expect(abs(steps - steps.rounded()) < 1e-9)

        #expect(SliderMath.value(atFraction: 0.33, in: 0...10, step: 1) == 3)
    }

    @Test func steppedValueNeverExceedsUpperBound() {
        // Step that does not divide the range evenly.
        #expect(SliderMath.value(atFraction: 1, in: 0...10, step: 3) == 9)
        #expect(SliderMath.value(atFraction: 0.99, in: 0...10, step: 4) <= 10)
    }

    @Test func logScalePutsGeometricMeanInTheMiddle() {
        #expect(abs(SliderMath.fraction(of: 1, in: 0.1...10, scale: .logarithmic) - 0.5) < 1e-9)
        #expect(SliderMath.fraction(of: 0.1, in: 0.1...10, scale: .logarithmic) == 0)
        #expect(SliderMath.fraction(of: 10, in: 0.1...10, scale: .logarithmic) == 1)
    }

    @Test func logScaleValueIsInverseOfFraction() {
        #expect(abs(SliderMath.value(atFraction: 0.5, in: 0.1...10, scale: .logarithmic) - 1) < 1e-9)
        #expect(abs(SliderMath.value(atFraction: 0.75, in: 0.1...10, scale: .logarithmic) - 10.0.squareRoot()) < 1e-9)
        #expect(abs(SliderMath.value(atFraction: 0.5, in: 0.1...10, step: 0.1, scale: .logarithmic) - 1) < 1e-9)
    }
}
