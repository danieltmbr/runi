import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A canvas container that displays the shared base-layer photo.
///
/// Reads the photo from the `VisualiserPhotoHolder` in the environment, decodes it,
/// and hands it to `content` as a `VisualiserPhotoLayer` sized to fill the canvas.
/// Each photo-based visualisation only applies its own effect to that layer:
///
/// ```swift
/// VisualiserPhotoCanvas { photo in
///     photo.visualEffect { content, proxy in
///         content.layerEffect(shader, maxSampleOffset: .zero)
///     }
/// }
/// ```
///
/// Shows an empty state while no photo is selected.
///
struct VisualiserPhotoCanvas<Content: View>: View {

    @Environment(\.visualiserPhoto)
    private var photoHolder

    @State
    private var image: Image?

    private let content: (VisualiserPhotoLayer) -> Content

    init(@ViewBuilder content: @escaping (VisualiserPhotoLayer) -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if let image {
                // `GeometryReader` measures the exact parent size so the layer can be
                // given a fixed frame that matches it precisely. This prevents the
                // image's aspect-ratio negotiation from making the view taller or
                // wider than the screen.
                GeometryReader { geometry in
                    content(VisualiserPhotoLayer(image: image, size: geometry.size))
                }
            } else {
                ContentUnavailableView(
                    "No Photo Selected",
                    systemImage: "photo",
                    description: Text("Choose a photo in the inspector to use it as the base layer.")
                )
            }
        }
        .task(id: photoHolder.version) {
            image = photoHolder.data.flatMap(makeImage)
        }
    }

    // MARK: - Private

    private func makeImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

// MARK: - Photo Layer

/// The base-layer photo, scaled to fill the canvas and clipped to its bounds.
///
/// `.clipped()` trims any overflow from the `.fill` content mode before a
/// `layerEffect` captures the layer.
///
struct VisualiserPhotoLayer: View {

    let image: Image

    let size: CGSize

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}
