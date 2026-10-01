import SwiftUI

/// A full-screen voronoi mosaic of a user-selected photo.
///
/// Every voronoi cell is filled with the photo's colour at the cell's feature
/// point. Along the run path the cells subdivide hierarchically, and around the
/// current run coordinate they subdivide further, so the mosaic becomes denser —
/// and the photo more detailed — on the path and denser still where the runner is.
/// The radii of those denser regions come from `VoronoiRadiusModulator`, which
/// either keeps them fixed or lets them follow the runner's effort.
///
/// The path reaches the shader as a `PathDistanceField` texture, rendered off the
/// main thread whenever the visible path changes.
///
/// Driven by a `VisualiserState` value (constructed from run metrics in the app layer)
/// and a `VoronoiPath` configuration binding for user-adjustable parameters.
/// The photo itself is owned by `VisualiserPhotoHolder` in the environment and
/// displayed through `VisualiserPhotoCanvas`.
///
public struct VoronoiPathView: View {
    
    private let modulator = VoronoiRadiusModulator()

    private let fieldRenderer = PathDistanceFieldRenderer()

    let state: VisualiserState

    var configuration: Binding<VoronoiPath>
    
    @State
    private var viewSize: CGSize = .zero
    
    @State
    private var visiblePath: [SIMD2<Float>] = []

    @State
    private var distanceField = PathDistanceField.empty

    public init(
        state: VisualiserState,
        configuration: Binding<VoronoiPath>
    ) {
        self.state = state
        self.configuration = configuration
    }

    public var body: some View {
        let radii       = modulator.radii(for: configuration.wrappedValue, state: state)
        let gridSize    = Float(configuration.wrappedValue.gridSize)
        let maxRadius   = Float(radii.max)
        let minRadius   = Float(radii.min)
        let pathRadius  = Float(configuration.wrappedValue.pathRadius)
        let coordinates = state.coordinates
        let fieldImage  = distanceField.image

        // `maxSampleOffset: .zero` is safe because the shader clamps all
        // sample positions to [0.5, size−0.5], never reading outside bounds.
        VisualiserPhotoCanvas { photo in
            photo
                .visualEffect { content, proxy in
                    content.layerEffect(
                        ShaderLibrary.bundle(.module).pathVoronoi(
                            .float2(proxy.size),
                            .float(gridSize),
                            .float(maxRadius),
                            .float(minRadius),
                            .float(pathRadius),
                            .float2(coordinates),
                            .float(PathDistanceField.extent),
                            .float(PathDistanceField.maxDistance),
                            .image(fieldImage)
                        ),
                        maxSampleOffset: .zero
                    )
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                    viewSize = newSize
                    recomputePath()
                }
                .onChange(of: state.path) { _, _ in
                    recomputePath()
                }
                .task(id: visiblePath) {
                    await renderDistanceField()
                }
        }
    }

    // MARK: - Distance Field

    /// Rasterises the visible path into the distance field the shader samples.
    /// Runs off the main thread; the previous field stays in place until it is done.
    ///
    private func renderDistanceField() async {
        let path = visiblePath
        let renderer = fieldRenderer
        let cgImage = await Task.detached(priority: .userInitiated) { renderer.render(path) }.value
        guard !Task.isCancelled else { return }
        distanceField = PathDistanceField(cgImage: cgImage)
    }
    
    // MARK: - LOD
    
    private func recomputePath() {
        let path = state.path
        guard path.count > 2, viewSize.height > 0 else {
            visiblePath = path
            return
        }
        
        let halfHeight = Float(viewSize.height / 2)
        
        let overviewEpsilon = 10 / halfHeight
        let detailEpsilon   = 1 / halfHeight
        
        let overviewIndices = PathSimplifier.rdp(path, epsilon: overviewEpsilon)
        let detailIndices   = visibleIndices(in: path, epsilon: detailEpsilon)
        
        let merged = overviewIndices.union(detailIndices)
        visiblePath = path.enumerated().compactMap { index, coord in
            merged.contains(index) ? coord : nil
        }
    }
    
    /// Returns RDP indices for the portion of the path visible in the current viewport.
    ///
    /// The viewport is expanded by 10% on each side so segments crossing the
    /// boundary are included and the path doesn't abruptly stop at the edge.
    ///
    private func visibleIndices(
        in path: [SIMD2<Float>],
        epsilon: Float
    ) -> Set<Int> {
        let aspectRatio = Float(viewSize.width / viewSize.height)
        let halfW: Float = aspectRatio * 1.1
        let halfH: Float = 1.1
        let minX: Float = -halfW, maxX = +halfW
        let minY: Float = -halfH, maxY = +halfH
        
        // Collect indices of visible points plus their immediate neighbours so
        // segments that cross the viewport boundary are drawn completely.
        var indices: [Int] = []
        for (i, p) in path.enumerated() {
            guard p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY else { continue }
            if i > 0 && indices.last != i - 1 { indices.append(i - 1) }
            indices.append(i)
            if i + 1 < path.count { indices.append(i + 1) }
        }
        
        guard indices.count > 2 else { return Set(indices) }
        
        // Deduplicate while preserving order (neighbours may be inserted twice).
        var seen = Set<Int>()
        let unique = indices.filter { seen.insert($0).inserted }
        let clipped = unique.map { path[$0] }
        return Set(PathSimplifier.rdp(clipped, epsilon: epsilon).map { unique[$0] })
    }
    
    // MARK: - Gestures
    
    
    private func clamp(_ value: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(hi, Swift.max(lo, value))
    }
}

#Preview {
    VoronoiPathView(state: .zero, configuration: .constant(VoronoiPath()))
}

// MARK: - Visualisation

extension VoronoiPath: Visualisation {

    /// Produces a `VoronoiView` driven by the given state and configuration binding.
    public func canvas(state: VisualiserState, binding: Binding<VoronoiPath>) -> some View {
        VoronoiPathView(state: state, configuration: binding)
    }
}
