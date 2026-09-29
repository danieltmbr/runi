import CoreKit
import Foundation

/// User-configurable parameters for the dynamic density voronoi visualisation.
///
/// This struct stores only the shader parameters — grid size and the radii of
/// the density increase around the runner — and whether those radii are fixed
/// or follow the runner's effort. The photo itself is transient view-layer state
/// managed by `VisualiserPhotoHolder` in the environment, keeping this config
/// small and cleanly serialisable.
///
/// `FormAdjustable` conformance lives in `VoronoiForm.swift`.
/// `Visualisation` conformance (canvas rendering) lives in `VoronoiView.swift`.
///
public struct Voronoi: Option, Equatable, Sendable {

    /// How the radii of the density increase are determined.
    public enum Mode: String, CaseIterable, Codable, Sendable {

        /// The radii always match `maxRadius` and `minRadius`.
        case fixed

        /// The radii follow the runner's effort. `maxRadius` and `minRadius`
        /// are the baseline at average effort. See `VoronoiRadiusModulator`.
        case dynamic
    }

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
    public var mode: Mode

    public var label: String { "Voronoi" }

    public var description: String {
        "A photo rendered as a voronoi mosaic. The cells subdivide into a finer pattern around the current run position. In dynamic mode the size and sharpness of that pattern follow the runner's effort."
    }

    public init(
        gridSize: Double = 6.0,
        maxRadius: Double = 0.55,
        minRadius: Double = 0.2,
        mode: Mode = .fixed
    ) {
        self.gridSize  = gridSize
        self.maxRadius = maxRadius
        self.minRadius = min(minRadius, maxRadius)
        self.mode      = mode
    }
}

// MARK: - Codable

extension Voronoi: Codable {

    private enum CodingKeys: String, CodingKey {
        case gridSize, maxRadius, minRadius, mode
    }

    /// Decodes `mode` leniently so configurations saved before
    /// the dynamic mode existed still load, as fixed.
    ///
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            gridSize: try container.decode(Double.self, forKey: .gridSize),
            maxRadius: try container.decode(Double.self, forKey: .maxRadius),
            minRadius: try container.decode(Double.self, forKey: .minRadius),
            mode: try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .fixed
        )
    }
}
