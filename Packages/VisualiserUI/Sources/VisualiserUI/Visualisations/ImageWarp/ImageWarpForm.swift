import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI
import CoreUI

// MARK: - FormAdjustable Conformance

extension ImageWarp: FormAdjustable {

    @MainActor
    public func form(for binding: Binding<ImageWarp>) -> some View {
        ImageWarpForm(value: binding)
    }
}

// MARK: - Form View

/// Configuration controls for `ImageWarp` shown via `AdjustableForm`.
///
/// PhotosPicker for selecting the source photo (written to `ImageWarpPhotoHolder`
/// in the environment), a segmented mode picker, and sliders for smoothness,
/// details, intensity, and radius. The radius slider is hidden in full-image mode.
///
private struct ImageWarpForm: View {

    @Binding
    var value: ImageWarp

    @Environment(\.imageWarpPhoto)
    private var photoHolder

    @State
    private var selectedItem: PhotosPickerItem?

    var body: some View {
        photoPicker

        Picker("Mode", selection: $value.mode) {
            ForEach(ImageWarp.Mode.allCases, id: \.self) { mode in
                Text(mode.formLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading) {
            Text("Smoothing")
                .font(.caption)
            Slider(value: $value.smoothness, in: 0...1)
        }

        VStack(alignment: .leading) {
            Text("Details")
                .font(.caption)
            Slider(value: $value.details, in: 1...12, step: 1)
        }

        VStack(alignment: .leading) {
            Text("Intensity")
                .font(.caption)
            Slider(value: $value.intensity, in: 0...1)
        }

        if value.mode != .full {
            VStack(alignment: .leading) {
                Text("Radius")
                    .font(.caption)
                Slider(value: $value.radius, in: 0.05...1.0)
            }
        }
    }

    // MARK: - Photo Picker

    @ViewBuilder
    private var photoPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo")
                .font(.caption)

            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(
                        photoHolder.data == nil ? "Select Photo" : "Change Photo",
                        systemImage: "photo"
                    )
                    .font(.caption)
                }

                Spacer()

                if photoHolder.data != nil {
                    Button("Remove") {
                        photoHolder.setData(nil)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: selectedItem) {
            guard let item = selectedItem,
                  let data = try? await item.loadTransferable(type: Data.self)
            else { return }
            photoHolder.setData(downsampledData(from: data))
        }
    }

    // MARK: - Private Helpers

    /// Downsamples image data to a screen-resolution thumbnail before storing.
    ///
    /// Uses `CGImageSource` for efficient decoding without loading the full original,
    /// then re-encodes as JPEG. A 1920 px max dimension keeps stored data at roughly
    /// 200–400 KB while retaining enough detail for full-screen rendering.
    ///
    private func downsampledData(from data: Data, maxDimension: Int = 1920) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }

        // JPEG does not support alpha. Strip the alpha channel by redrawing into an
        // opaque RGB bitmap — otherwise CGImageDestinationFinalize fails on images
        // with AlphaPremulLast pixel format (common for HEIC photos from iOS).
        let cgImage = strippingAlpha(from: thumbnail)

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
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

// MARK: - Private Mode Labels

private extension ImageWarp.Mode {

    var formLabel: String {
        switch self {
        case .full:     return "Full"
        case .position: return "Position"
        case .path:     return "Path"
        }
    }
}
