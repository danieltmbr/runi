import CoreKit
import Foundation

/// User-configurable parameters for the voronoi path visualisation.
///
/// The density field has two parts: a thin band along the run path with its
/// own `pathRadius`, and a wider region around the runner described by
/// `maxRadius` / `minRadius`. Only the runner's radii follow the effort in
/// dynamic mode; the path band stays as set.
///
/// `FormAdjustable` conformance lives in `VoronoiPathForm.swift`.
/// `Visualisation` conformance (canvas rendering) lives in `VoronoiPathView.swift`.
///
public struct VoronoiPath: Option, Equatable, Sendable {

    /// Number of base voronoi cells across half of the canvas' short side (1–60).
    public var gridSize: Double

    /// Radius of the density increase around the runner at the coarsest level,
    /// in normalised coordinate space where 1 is half of the canvas' short side.
    /// Lowering it below `minRadius` drags `minRadius` down with it.
    public var maxRadius: Double {
        didSet { minRadius = min(minRadius, maxRadius) }
    }

    /// Radius of the density increase around the runner at the deepest
    /// subdivision level, in normalised coordinate space (0.05–`maxRadius`).
    public var minRadius: Double

    /// Half width of the denser band along the run path, in normalised coordinate space.
    public var pathRadius: Double

    /// Whether the runner's radii are fixed or follow the runner's effort.
    public var mode: Voronoi.Mode

    // MARK: - Option

    public var label: String { "Voronoi Path" }

    public var description: String {
        "Dynamic density Voronoi with high definition on the run path."
    }

    public init(
        gridSize: Double = 6.0,
        maxRadius: Double = 0.3,
        minRadius: Double = 0.15,
        pathRadius: Double = 0.12,
        mode: Voronoi.Mode = .fixed
    ) {
        self.gridSize   = gridSize
        self.maxRadius  = maxRadius
        self.minRadius  = min(minRadius, maxRadius)
        self.pathRadius = pathRadius
        self.mode       = mode
    }
}

// MARK: - Codable

extension VoronoiPath: Codable {

    private enum CodingKeys: String, CodingKey {
        case gridSize, maxRadius, minRadius, pathRadius, mode
    }

    /// Decodes `pathRadius` and `mode` leniently so configurations saved
    /// before they existed still load, with their defaults.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = VoronoiPath()
        self.init(
            gridSize: try container.decode(Double.self, forKey: .gridSize),
            maxRadius: try container.decode(Double.self, forKey: .maxRadius),
            minRadius: try container.decode(Double.self, forKey: .minRadius),
            pathRadius: try container.decodeIfPresent(Double.self, forKey: .pathRadius) ?? defaults.pathRadius,
            mode: try container.decodeIfPresent(Voronoi.Mode.self, forKey: .mode) ?? defaults.mode
        )
    }
}
