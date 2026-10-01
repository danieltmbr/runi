import CoreGraphics
import Metal
import VisualiserUI

/// Encodes video frames of the `Warp` visualisation.
///
/// Mirrors what `WarpView` passes to `runWarpShader`, at the default
/// zoom and offset since the export has no gestures.
///
struct WarpFrameEncoder: VideoFrameEncoder {

    let fragmentFunction = "export_warp_fragment"

    private let logicalSize: CGSize

    private let paletteTexture: MTLTexture?

    private let warp: Warp

    init(warp: Warp, context: VideoFrameEncoderContext) {
        self.logicalSize = context.logicalSize
        self.warp = warp
        self.paletteTexture = Self.makePaletteTexture(device: context.device, palette: warp.palette)
    }

    func encode(_ state: VisualiserState, into encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms(
            time: state.time,
            octaves: Float(warp.details),
            h: shaderH(elevation: state.elevation),
            scale: 0.007,
            speed: state.speed,
            heartRate: state.heartRate,
            dirX: state.direction.x,
            dirY: state.direction.y,
            offsetX: 0,
            offsetY: 0,
            sizeX: Float(logicalSize.width),
            sizeY: Float(logicalSize.height)
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)

        if let paletteTexture {
            encoder.setFragmentTexture(paletteTexture, index: 0)
        }
    }

    // MARK: - Private

    private func shaderH(elevation: Float) -> Float {
        let elevationOffset = (1.0 - Double(elevation) - 0.5) * 0.3
        return Float(max(0, min(1, warp.smoothness + elevationOffset)))
    }

    private static func makePaletteTexture(device: MTLDevice, palette: ColorPalette) -> MTLTexture? {
        let cgImage = PaletteGradientRenderer.render(palette)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: cgImage.width,
            height: cgImage.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let region = MTLRegion(origin: MTLOriginMake(0, 0, 0), size: MTLSizeMake(cgImage.width, 1, 1))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: cgImage.width, height: 1, bitsPerComponent: 8,
                            bytesPerRow: cgImage.width * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: 1))
        if let data = ctx.data {
            texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: cgImage.width * 4)
        }
        return texture
    }
}

// MARK: - Uniforms (must match `WarpUniforms` in export.metal)

private extension WarpFrameEncoder {

    struct Uniforms {
        var time: Float
        var octaves: Float
        var h: Float
        var scale: Float
        var speed: Float
        var heartRate: Float
        var dirX: Float
        var dirY: Float
        var offsetX: Float
        var offsetY: Float
        var sizeX: Float
        var sizeY: Float
    }
}

// MARK: - Exportable

extension Warp: VideoExportable {

    func makeFrameEncoder(in context: VideoFrameEncoderContext) throws -> any VideoFrameEncoder {
        WarpFrameEncoder(warp: self, context: context)
    }
}
