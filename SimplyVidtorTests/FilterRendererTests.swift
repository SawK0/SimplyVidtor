import CoreImage
import Testing
@testable import SimplyVidtor

struct FilterRendererTests {
    private let context = CIContext()

    private func image(r: Double, g: Double, b: Double) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func color(of image: CIImage) -> (r: Int, g: Int, b: Int) {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 4, y: 4, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    @Test func warmAndCoolShiftWhiteBalance() {
        let gray = image(r: 0.5, g: 0.5, b: 0.5)
        let warm = color(of: FilterRenderer.apply(ClipFilter(preset: .warm), to: gray))
        let cool = color(of: FilterRenderer.apply(ClipFilter(preset: .cool), to: gray))
        #expect(warm.r > warm.b, "Warm should lean red, got \(warm)")
        #expect(cool.b > cool.r, "Cool should lean blue, got \(cool)")
    }

    @Test func monoRemovesColor() {
        let mono = color(of: FilterRenderer.apply(ClipFilter(preset: .mono), to: image(r: 1, g: 0.8, b: 0)))
        #expect(abs(mono.r - mono.b) < 8 && abs(mono.r - mono.g) < 8, "Got \(mono)")
    }

    @Test func intensityBlendsWithOriginal() {
        let yellow = image(r: 1, g: 0.8, b: 0)
        let none = color(of: FilterRenderer.apply(ClipFilter(preset: .mono, intensity: 0), to: yellow))
        let half = color(of: FilterRenderer.apply(ClipFilter(preset: .mono, intensity: 0.5), to: yellow))
        let full = color(of: FilterRenderer.apply(ClipFilter(preset: .mono), to: yellow))
        #expect(none == color(of: yellow))
        #expect(half.r - half.b < none.r - none.b && half.r - half.b > full.r - full.b)
    }

    @Test(arguments: FilterPreset.allCases)
    func presetKeepsExtent(preset: FilterPreset) {
        let source = image(r: 0.3, g: 0.6, b: 0.9)
        #expect(FilterRenderer.apply(ClipFilter(preset: preset), to: source).extent == source.extent)
    }

    @Test func neutralAdjustmentsLeaveImageUnchanged() {
        let source = image(r: 0.3, g: 0.6, b: 0.9)
        #expect(FilterRenderer.apply(ClipAdjustments(), to: source) === source)
    }

    @Test func brightnessAndSaturationMoveTheRightWay() {
        let source = image(r: 0.8, g: 0.5, b: 0.2)
        let original = color(of: source)
        let brighter = color(of: FilterRenderer.apply(ClipAdjustments(brightness: 0.5), to: source))
        let desaturated = color(of: FilterRenderer.apply(ClipAdjustments(saturation: -1), to: source))
        #expect(brighter.g > original.g)
        #expect(abs(desaturated.r - desaturated.b) < 8, "Got \(desaturated)")
    }

    @Test func warmthShiftsWhiteBalance() {
        let gray = image(r: 0.5, g: 0.5, b: 0.5)
        let warm = color(of: FilterRenderer.apply(ClipAdjustments(warmth: 1), to: gray))
        let cool = color(of: FilterRenderer.apply(ClipAdjustments(warmth: -1), to: gray))
        #expect(warm.r > warm.b && cool.b > cool.r)
    }
}
