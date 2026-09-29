import CoreGraphics
import Foundation
import ImageIO

/// Downsamples raw photo bytes to a screen-resolution JPEG.
///
/// Uses `CGImageSource` for efficient decoding without loading the full original,
/// then re-encodes as JPEG. The default 1920 px max dimension keeps stored data at
/// roughly 200–400 KB while retaining enough detail for full-screen rendering.
///
struct PhotoDownsampler {

    /// Longest side of the downsampled photo, in pixels.
    let maxDimension: Int

    /// JPEG compression quality in `[0, 1]`.
    let compressionQuality: Double

    init(maxDimension: Int = 1920, compressionQuality: Double = 0.7) {
        self.maxDimension = maxDimension
        self.compressionQuality = compressionQuality
    }

    /// Returns the downsampled JPEG bytes, or `nil` if `data` cannot be decoded or re-encoded.
    func downsample(_ data: Data) -> Data? {
        guard let thumbnail = thumbnail(from: data) else { return nil }

        // JPEG does not support alpha. Strip the alpha channel by redrawing into an
        // opaque RGB bitmap — otherwise CGImageDestinationFinalize fails on images
        // with AlphaPremulLast pixel format (common for HEIC photos from iOS).
        return jpegData(from: strippingAlpha(from: thumbnail))
    }

    // MARK: - Private

    private func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func jpegData(from image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }

    /// Redraws `image` into an opaque RGB bitmap, stripping any alpha channel.
    /// Returns the original image unchanged if the conversion fails.
    private func strippingAlpha(from image: CGImage) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}
