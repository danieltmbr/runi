import CoreGraphics
import Foundation
import Metal
import VisualiserUI

/// Encodes the visualisation-specific part of an exported video frame.
///
/// `VideoRenderer` owns everything the visualisations share — the Metal device,
/// the render target and the video writer. A frame encoder owns what differs:
/// which fragment function of `export.metal` draws the visualisation, and the
/// uniforms, buffers and textures that function reads.
///
/// Resources that stay the same for the whole video (palette, path, photo)
/// are prepared once when the encoder is created.
///
protocol VideoFrameEncoder {

    /// Name of the fragment function in `export.metal` that renders the visualisation.
    ///
    var fragmentFunction: String { get }

    /// Binds the uniforms, buffers and textures the fragment function needs
    /// to render the given state of the run.
    ///
    func encode(_ state: VisualiserState, into encoder: MTLRenderCommandEncoder)
}

// MARK: - Context

/// Everything a visualisation may need to prepare its frame encoder.
///
struct VideoFrameEncoderContext {

    let device: MTLDevice

    /// Viewport size in logical points used for shader coordinate mapping.
    ///
    let logicalSize: CGSize

    /// Physical render resolution in pixels.
    ///
    let resolution: CGSize

    /// Normalised coordinates of the full path of the run (-1, 1).
    ///
    let path: [SIMD2<Float>]

    /// Raw bytes of the base-layer photo; `nil` when no photo is selected.
    ///
    let photo: Data?
}

// MARK: - Exportable

/// A visualisation that can be rendered to video.
///
/// Conformances live next to their frame encoder. A visualisation without
/// a conformance cannot be exported and `VideoRenderer` reports it as unsupported.
///
protocol VideoExportable {

    /// Creates the frame encoder that renders this visualisation with its current configuration.
    ///
    func makeFrameEncoder(in context: VideoFrameEncoderContext) throws -> any VideoFrameEncoder
}
