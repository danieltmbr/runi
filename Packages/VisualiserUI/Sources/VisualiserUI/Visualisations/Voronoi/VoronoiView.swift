import SwiftUI

/// A full-screen voronoi mosaic of a user-selected photo.
///
/// Every voronoi cell is filled with the photo's colour at the cell's feature
/// point. Around the current run coordinate the cells subdivide hierarchically,
/// so the mosaic becomes denser — and the photo more detailed — where the runner is.
///
/// Driven by a `VisualiserState` value (constructed from run metrics in the app layer)
/// and a `Voronoi` configuration binding for user-adjustable parameters.
/// The photo itself is owned by `VisualiserPhotoHolder` in the environment and
/// displayed through `VisualiserPhotoCanvas`.
///
public struct VoronoiView: View {

    let state: VisualiserState

    var configuration: Binding<Voronoi>

    public init(state: VisualiserState, configuration: Binding<Voronoi>) {
        self.state = state
        self.configuration = configuration
    }

    public var body: some View {
        let gridSize    = Float(configuration.wrappedValue.gridSize)
        let maxRadius   = Float(configuration.wrappedValue.maxRadius)
        let minRadius   = Float(configuration.wrappedValue.minRadius)
        let coordinates = state.coordinates

        // `maxSampleOffset: .zero` is safe because the shader clamps all
        // sample positions to [0.5, size−0.5], never reading outside bounds.
        VisualiserPhotoCanvas { photo in
            photo.visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).dynamicDensityVoronoi(
                        .float2(proxy.size),
                        .float(gridSize),
                        .float(maxRadius),
                        .float(minRadius),
                        .float2(coordinates)
                    ),
                    maxSampleOffset: .zero
                )
            }
        }
    }
}

#Preview {
    VoronoiView(state: .zero, configuration: .constant(Voronoi()))
}

// MARK: - Visualisation

extension Voronoi: Visualisation {

    /// Produces a `VoronoiView` driven by the given state and configuration binding.
    public func canvas(state: VisualiserState, binding: Binding<Voronoi>) -> some View {
        VoronoiView(state: state, configuration: binding)
    }
}
