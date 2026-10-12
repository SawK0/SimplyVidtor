import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image recipes for adjustments and `FilterPreset`, shared by the
/// compositor and panel thumbnails.
nonisolated enum FilterRenderer {
    /// Turns `image` by clockwise quarter turns, then keeps the `crop` region.
    static func framed(_ image: CIImage, rotation: Int, crop: CropRect?) -> CIImage {
        let turned = switch ((rotation % 4) + 4) % 4 {
        case 1: image.oriented(.right)
        case 2: image.oriented(.down)
        case 3: image.oriented(.left)
        default: image
        }
        guard let crop, !crop.isFull else { return turned }
        let e = turned.extent
        // Crop rects are top-left based; Core Image is bottom-left based.
        return turned.cropped(to: CGRect(
            x: e.minX + crop.x * e.width,
            y: e.minY + (1 - crop.maxY) * e.height,
            width: crop.width * e.width,
            height: crop.height * e.height
        ))
    }

    /// Pixel size of a frame of `size` after `framed`.
    static func framedSize(_ size: CGSize, rotation: Int, crop: CropRect?) -> CGSize {
        let turned = rotation % 2 == 1 ? CGSize(width: size.height, height: size.width) : size
        let crop = crop ?? .full
        return CGSize(width: turned.width * crop.width, height: turned.height * crop.height)
    }

    /// Rotated copy of a still frame, for the crop editor.
    @concurrent
    static func rotated(_ image: CGImage, quarterTurns: Int) async -> CGImage? {
        let turned = framed(CIImage(cgImage: image), rotation: quarterTurns, crop: nil)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(turned, from: turned.extent)
    }

    /// Adjustments first, then the filter on top.
    static func apply(_ adjustments: ClipAdjustments, filter: ClipFilter?, to image: CIImage) -> CIImage {
        let adjusted = apply(adjustments, to: image)
        return filter.map { apply($0, to: adjusted) } ?? adjusted
    }

    static func apply(_ adjustments: ClipAdjustments, to image: CIImage) -> CIImage {
        guard !adjustments.isIdentity else { return image }
        var output = image
        if adjustments.brightness != 0 || adjustments.contrast != 0 || adjustments.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.brightness = Float(adjustments.brightness * 0.3)
            controls.contrast = Float(1 + adjustments.contrast * 0.5)
            controls.saturation = Float(1 + adjustments.saturation)
            output = controls.outputImage ?? output
        }
        if adjustments.warmth != 0 {
            output = whiteBalance(output, targetKelvin: 6500 - adjustments.warmth * 2500)
        }
        return output.cropped(to: image.extent)
    }

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
            return whiteBalance(image, targetKelvin: preset == .warm ? 4500 : 9000)
        case .chrome: filter = CIFilter.photoEffectChrome()
        case .fade: filter = CIFilter.photoEffectFade()
        case .instant: filter = CIFilter.photoEffectInstant()
        case .mono: filter = CIFilter.photoEffectMono()
        case .noir: filter = CIFilter.photoEffectNoir()
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    /// Lower targets warm the image, higher ones cool it.
    private static func whiteBalance(_ image: CIImage, targetKelvin: Double) -> CIImage {
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: 6500, y: 0)
        f.targetNeutral = CIVector(x: targetKelvin, y: 0)
        return f.outputImage ?? image
    }
}
