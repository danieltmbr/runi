import SwiftUI

/// A full-screen image warp visualisation driven by domain warping displacement.
///
/// Displays a user-selected photo with organic geometric distortion applied via
/// `layerEffect()` — sampling the layer at a displaced position rather than simply
/// modifying pixel colours. Three modes control the distortion area:
///   - **Full**: the entire image is warped.
///   - **Position**: warp is applied within a configurable radius around the current
///     run coordinate, fading smoothly to the undistorted photo at the boundary.
///   - **Path**: warp is applied along the run path with a radius falloff,
///     with extra intensity near the current position.
///
/// The photo itself is owned by `ImageWarpPhotoHolder` in the environment —
/// `ImageWarpView` is the primary reader while `ImageWarpForm` is the writer.
/// This keeps the transient photo bytes out of the JSON-serialised `ImageWarp` config.
///
public struct ImageWarpView: View {

    let state: VisualiserState

    var configuration: Binding<ImageWarp>

    @Environment(\.imageWarpPhoto)
    private var photoHolder

    @State
    private var photoImage: Image?

    @State
    private var visiblePath: [SIMD2<Float>] = []

    public init(state: VisualiserState, configuration: Binding<ImageWarp>) {
        self.state = state
        self.configuration = configuration
    }

    public var body: some View {
        let animTime    = state.time
        let octaves     = Float(configuration.wrappedValue.details)
        let h           = shaderH(elevation: state.elevation)
        let intensity   = Float(configuration.wrappedValue.intensity)
        let modeFloat   = modeValue(for: configuration.wrappedValue.mode)
        let coordinates = state.coordinates
        let direction   = state.direction
        let radius      = Float(configuration.wrappedValue.radius)
        let pathData    = visiblePath.withUnsafeBytes { Data($0) }

        Group {
            if let photoImage {
                // `GeometryReader` measures the exact parent size so we can give
                // the image a fixed frame that matches it precisely. This prevents
                // the image's aspect-ratio negotiation from making the view taller
                // or wider than the screen. `.clipped()` trims any overflow from
                // the `.fill` content mode before `layerEffect` captures the layer.
                // `maxSampleOffset: .zero` is safe because the shader clamps all
                // sample positions to [0.5, size−0.5], never reading outside bounds.
                GeometryReader { geo in
                    photoImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .visualEffect { content, proxy in
                            content.layerEffect(
                                ShaderLibrary.bundle(.module).imageWarpShader(
                                    .float2(proxy.size),
                                    .float(animTime),
                                    .float(octaves),
                                    .float(h),
                                    .float(intensity),
                                    .float(modeFloat),
                                    .float2(coordinates),
                                    .float2(direction),
                                    .float(radius),
                                    .data(pathData)
                                ),
                                maxSampleOffset: .zero
                            )
                        }
                }
            } else {
                ContentUnavailableView(
                    "No Photo Selected",
                    systemImage: "photo",
                    description: Text("Choose a photo in the inspector to apply warp effects.")
                )
            }
        }
        .task(id: photoHolder.version) {
            loadPhotoImage()
        }
        .onAppear {
            updatePath()
        }
        .onChange(of: configuration.wrappedValue.mode) { _, _ in
            updatePath()
        }
        .onChange(of: state.path) { _, _ in
            updatePath()
        }
    }

    // MARK: - Private

    private func shaderH(elevation: Float) -> Float {
        let elevationOffset = (1.0 - Double(elevation) - 0.5) * 0.3
        return Float(max(0, min(1, configuration.wrappedValue.smoothness + elevationOffset)))
    }

    private func modeValue(for mode: ImageWarp.Mode) -> Float {
        switch mode {
        case .full:     return 0
        case .position: return 1
        case .path:     return 2
        }
    }

    private func loadPhotoImage() {
        guard let data = photoHolder.data else {
            photoImage = nil
            return
        }
        photoImage = makeImage(from: data)
    }

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

    private func updatePath() {
        guard configuration.wrappedValue.mode == .path else {
            visiblePath = []
            return
        }
        let path = state.path
        guard path.count > 2 else {
            visiblePath = path
            return
        }
        let indices = PathSimplifier.rdp(path, epsilon: 0.005)
        visiblePath = path.enumerated().compactMap { i, p in indices.contains(i) ? p : nil }
    }
}

#Preview {
    ImageWarpView(state: .zero, configuration: .constant(ImageWarp()))
}

// MARK: - Visualisation

extension ImageWarp: Visualisation {

    /// Produces an `ImageWarpView` driven by the given state and configuration binding.
    public func canvas(state: VisualiserState, binding: Binding<ImageWarp>) -> some View {
        ImageWarpView(state: state, configuration: binding)
    }
}
