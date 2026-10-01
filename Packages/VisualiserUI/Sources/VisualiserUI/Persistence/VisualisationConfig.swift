import Foundation

/// Codable representation of the finite set of `Visualisation` conformers.
///
/// Encodes as a single-key dictionary — `{"warp": {...}}` or `{"runPath": {...}}` —
/// so the case discriminator and associated value are stored together.
/// Unknown cases degrade gracefully to `.warp` on decode.
///
/// `Codable` is implemented explicitly as `nonisolated` to prevent Swift 6
/// from treating the conformance as `@MainActor`-isolated.
///
public enum VisualisationConfig: Sendable {

    case warp(Warp)
    case imageWarp(ImageWarp)
    case runPath(RunPath)
    case colors(Gradients)
    case voronoi(Voronoi)
    case voronoiPath(VoronoiPath)

    // MARK: - Init

    public init(_ visualisation: any Visualisation) throws {
        switch visualisation {
        case let v as Warp:      self = .warp(v)
        case let v as ImageWarp: self = .imageWarp(v)
        case is RunPath:         self = .runPath(RunPath())
        case is Gradients:       self = .colors(Gradients())
        case let v as Voronoi:   self = .voronoi(v)
        case let v as VoronoiPath: self = .voronoiPath(v)
        default:
            throw EncodingError.invalidValue(
                visualisation,
                .init(codingPath: [], debugDescription: "Unknown Visualisation type: \(type(of: visualisation))")
            )
        }
    }

    // MARK: - Resolve

    public func resolve() -> any Visualisation {
        switch self {
        case .warp(let v):      return v
        case .imageWarp(let v): return v
        case .runPath:          return RunPath()
        case .colors:           return Gradients()
        case .voronoi(let v):   return v
        case .voronoiPath(let v): return v
        }
    }
}

// MARK: - Codable

extension VisualisationConfig: Codable {

    private enum CodingKeys: String, CodingKey {
        case warp, imageWarp, runPath, colors, voronoi, voronoiPath
    }

    public nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.warp) {
            self = .warp(try container.decode(Warp.self, forKey: .warp))
        } else if container.contains(.imageWarp) {
            self = .imageWarp(try container.decode(ImageWarp.self, forKey: .imageWarp))
        } else if container.contains(.runPath) {
            self = .runPath(try container.decode(RunPath.self, forKey: .runPath))
        } else if container.contains(.colors) {
            self = .colors(try container.decode(Gradients.self, forKey: .colors))
        } else if container.contains(.voronoi) {
            self = .voronoi(try container.decode(Voronoi.self, forKey: .voronoi))
        } else if container.contains(.voronoiPath) {
            self = .voronoiPath(try container.decode(VoronoiPath.self, forKey: .voronoiPath))
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown VisualisationConfig case")
            )
        }
    }

    public nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .warp(let v):      try container.encode(v, forKey: .warp)
        case .imageWarp(let v): try container.encode(v, forKey: .imageWarp)
        case .runPath(let v):   try container.encode(v, forKey: .runPath)
        case .colors(let v):    try container.encode(v, forKey: .colors)
        case .voronoi(let v):   try container.encode(v, forKey: .voronoi)
        case .voronoiPath(let v): try container.encode(v, forKey: .voronoiPath)
        }
    }
}
