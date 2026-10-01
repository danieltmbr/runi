import CoreKit
import Foundation

public struct VoronoiPath: Option, Equatable, Sendable, Codable {
    
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
    
    /// Whether the radii are fixed or follow the runner's effort.
    public var mode: Voronoi.Mode

    // MARK: - Option

    public var label: String { "Voronoi Path" }

    public var description: String {
        "Dynamic density Voronoi with high definition on the run path."
    }
    
    public init(
        gridSize: Double = 6.0,
        maxRadius: Double = 0.55,
        minRadius: Double = 0.2,
        mode: Voronoi.Mode = .fixed
    ) {
        self.gridSize  = gridSize
        self.maxRadius = maxRadius
        self.minRadius = min(minRadius, maxRadius)
        self.mode      = mode
    }
}
