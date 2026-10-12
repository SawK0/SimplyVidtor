import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image recipes for `FilterPreset`, shared by the compositor and panel thumbnails.
nonisolated enum FilterRenderer {
    static func apply(_ filter: ClipFilter, to image: CIImage) -> CIImage {
        let intensity = min(max(filter.intensity, 0), 1)
        guard intensity > 0 else { return image }
        let filtered = full(filter.preset, image).cropped(to: image.extent)
        guard intensity < 1 else { return filtered }
        let blend = CIFilter.dissolveTransition()
        blend.inputImage = image
        blend.targetImage = filtered
        blend.time = Float(intensity)
        return blend.outputImage?.cropped(to: image.extent) ?? filtered
    }

    /// Small swatches of `image` with each preset at full strength, for the panel.
    @concurrent
    static func previews(of image: CGImage) async -> [FilterPreset: CGImage] {
        let source = CIImage(cgImage: image)
        let context = CIContext(options: [.cacheIntermediates: false])
        var result: [FilterPreset: CGImage] = [:]
        for preset in FilterPreset.allCases {
            result[preset] = context.createCGImage(apply(ClipFilter(preset: preset), to: source), from: source.extent)
        }
        return result
    }

    private static func full(_ preset: FilterPreset, _ image: CIImage) -> CIImage {
        let filter: (any CIFilter & CIFilterProtocol)
        switch preset {
        case .vivid:
            let f = CIFilter.vibrance()
            f.amount = 1
            filter = f
        case .warm, .cool:
            let f = CIFilter.temperatureAndTint()
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: preset == .warm ? 4500 : 9000, y: 0)
            filter = f
        case .chrome: filter = CIFilter.photoEffectChrome()
        case .fade: filter = CIFilter.photoEffectFade()
        case .instant: filter = CIFilter.photoEffectInstant()
        case .mono: filter = CIFilter.photoEffectMono()
        case .noir: filter = CIFilter.photoEffectNoir()
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }
}
