import CoreKit
import Foundation

/// User-configurable parameters for the dynamic density voronoi visualisation.
///
/// This struct stores only the shader parameters — grid size and the radii of
/// the density increase around the runner. The photo itself is transient
/// view-layer state managed by `VisualiserPhotoHolder` in the environment,
/// keeping this config small and cleanly serialisable.
///
/// `FormAdjustable` conformance lives in `VoronoiForm.swift`.
/// `Visualisation` conformance (canvas rendering) lives in `VoronoiView.swift`.
///
public struct Voronoi: Option, Equatable, Sendable, Codable {

    /// Number of base voronoi cells across half of the canvas' short side (1–60).
    public var gridSize: Double

    /// Radius of the density increase at the coarsest level, in normalised
    /// coordinate space where 1 is half of the canvas' short side (0.1–1.5).
    /// Lowering it below `minRadius` drags `minRadius` down with it.
    public var maxRadius: Double {
        didSet { minRadius = min(minRadius, maxRadius) }
    }

    /// Radius of the density increase at the deepest subdivision level,
    /// in normalised coordinate space (0.05–`maxRadius`).
    public var minRadius: Double

    public var label: String { "Voronoi" }

    public var description: String {
        "A photo rendered as a voronoi mosaic. The cells subdivide into a finer pattern around the current run position."
    }

    public init(
        gridSize: Double = 6.0,
        maxRadius: Double = 0.55,
        minRadius: Double = 0.2
    ) {
        self.gridSize  = gridSize
        self.maxRadius = maxRadius
        self.minRadius = min(minRadius, maxRadius)
    }
}
