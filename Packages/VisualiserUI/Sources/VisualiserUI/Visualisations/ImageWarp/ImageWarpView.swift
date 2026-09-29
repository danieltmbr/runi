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
/// The photo itself is owned by `VisualiserPhotoHolder` in the environment and
/// displayed through `VisualiserPhotoCanvas`. This keeps the transient photo bytes
/// out of the JSON-serialised `ImageWarp` config.
///
public struct ImageWarpView: View {

    let state: VisualiserState

    var configuration: Binding<ImageWarp>

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

        // `maxSampleOffset: .zero` is safe because the shader clamps all
        // sample positions to [0.5, size−0.5], never reading outside bounds.
        VisualiserPhotoCanvas { photo in
            photo.visualEffect { content, proxy in
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
