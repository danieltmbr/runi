import CoreGraphics
import Foundation
import ImageIO
import Metal

/// Turns the base-layer photo into a texture that covers the exported canvas.
///
/// The photo is drawn aspect-filled and centred into a bitmap of the requested
/// size, mirroring how `VisualiserPhotoLayer` lays it out on screen. Fragment
/// functions can therefore sample it with plain normalised canvas coordinates,
/// exactly like the live shaders sample their SwiftUI layer.
///
struct PhotoTextureMaker {

    let device: MTLDevice

    /// Returns a texture of the given pixel size filled with the photo.
    ///
    func makeTexture(from photo: Data, filling size: CGSize) throws -> MTLTexture {
        let image = try decodedImage(from: photo)
        let bitmap = try aspectFilledBitmap(of: image, width: Int(size.width), height: Int(size.height))
        return try texture(from: bitmap)
    }

    // MARK: - Private

    private func decodedImage(from photo: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(photo as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw VideoRenderer.RenderError.photoUnreadable }
        return image
    }

    private func aspectFilledBitmap(of image: CGImage, width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw VideoRenderer.RenderError.setupFailed("Could not create photo bitmap") }

        context.interpolationQuality = .high
        context.draw(image, in: aspectFillRect(for: image, width: CGFloat(width), height: CGFloat(height)))
        return context
    }

    /// The centred rect the image must be drawn in to cover the whole canvas.
    ///
    private func aspectFillRect(for image: CGImage, width: CGFloat, height: CGFloat) -> CGRect {
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = max(width / imageWidth, height / imageHeight)
        let scaledWidth = imageWidth * scale
        let scaledHeight = imageHeight * scale
        return CGRect(
            x: (width - scaledWidth) / 2,
            y: (height - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    private func texture(from bitmap: CGContext) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: bitmap.width,
            height: bitmap.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor),
              let bytes = bitmap.data
        else { throw VideoRenderer.RenderError.setupFailed("Could not create photo texture") }

        texture.replace(
            region: MTLRegion(origin: MTLOriginMake(0, 0, 0), size: MTLSizeMake(bitmap.width, bitmap.height, 1)),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bitmap.bytesPerRow
        )
        return texture
    }
}
