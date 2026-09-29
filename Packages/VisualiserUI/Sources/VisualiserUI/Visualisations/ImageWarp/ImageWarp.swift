import CoreKit
import Foundation

/// User-configurable shader parameters for the image warp visualisation.
///
/// This struct stores only the animation parameters — smoothness, detail,
/// intensity, radius, and coverage mode. The photo itself is transient
/// view-layer state managed by `VisualiserPhotoHolder` in the environment,
/// keeping this config small and cleanly serialisable.
///
/// `FormAdjustable` conformance lives in `ImageWarpForm.swift`.
/// `Visualisation` conformance (canvas rendering) lives in `ImageWarpView.swift`.
///
/// - Note: Future improvement — the "base layer" concept (procedural noise vs.
///   a user photo) should eventually be selectable at the visualisation level,
///   not buried inside a single option. `VisualiserPhotoHolder` is the seed of
///   that architecture.
///
public struct ImageWarp: Option, Equatable, Sendable, Codable {

    /// fBM H parameter offset — controls global smoothness (0–1).
    public var smoothness: Double

    /// fBM octave count — controls detail level (1–12).
    public var details: Double

    /// Displacement strength — how far each pixel is pushed (0–1).
    public var intensity: Double

    /// Warp falloff radius in normalised coordinate space (0.05–1.0).
    /// Only active in `.position` and `.path` modes.
    public var radius: Double

    /// Which region of the photo receives the warp distortion.
    public var mode: Mode

    public var label: String { "Image Warp" }

    public var description: String {
        "Domain warp distortion applied to a photo. Select a coverage mode: full image, around the current run position, or along the run path."
    }

    /// Which region of the image receives the warp distortion.
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case full
        case position
        case path
    }

    public init(
        smoothness: Double = 0.8,
        details: Double = 5.0,
        intensity: Double = 0.5,
        radius: Double = 0.3,
        mode: Mode = .full
    ) {
        self.smoothness = smoothness
        self.details    = details
        self.intensity  = intensity
        self.radius     = radius
        self.mode       = mode
    }
}
