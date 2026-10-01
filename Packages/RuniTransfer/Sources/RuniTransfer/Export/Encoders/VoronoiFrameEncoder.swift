import CoreGraphics
import Metal
import VisualiserUI

/// Encodes video frames of the `Voronoi` visualisation.
///
/// Mirrors what `VoronoiView` passes to `dynamicDensityVoronoi`: the radii come
/// from the same `VoronoiRadiusModulator`, so a dynamic density field follows the
/// runner's effort in the video exactly as it does on screen. The photo is
/// uploaded once as a texture covering the canvas.
///
struct VoronoiFrameEncoder: VideoFrameEncoder {

    let fragmentFunction = "export_voronoi_fragment"

    private let logicalSize: CGSize

    private let modulator = VoronoiRadiusModulator()

    private let photoTexture: MTLTexture

    private let voronoi: Voronoi

    init(voronoi: Voronoi, context: VideoFrameEncoderContext) throws {
        guard let photo = context.photo else {
            throw VideoRenderer.RenderError.photoMissing
        }
        self.logicalSize = context.logicalSize
        self.voronoi = voronoi
        self.photoTexture = try PhotoTextureMaker(device: context.device)
            .makeTexture(from: photo, filling: context.resolution)
    }

    func encode(_ state: VisualiserState, into encoder: MTLRenderCommandEncoder) {
        let radii = modulator.radii(for: voronoi, state: state)
        var uniforms = Uniforms(
            sizeX: Float(logicalSize.width),
            sizeY: Float(logicalSize.height),
            gridSize: Float(voronoi.gridSize),
            maxRadius: Float(radii.max),
            minRadius: Float(radii.min),
            coordinatesX: state.coordinates.x,
            coordinatesY: state.coordinates.y
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)
        encoder.setFragmentTexture(photoTexture, index: 0)
    }
}

// MARK: - Uniforms (must match `VoronoiUniforms` in export.metal)

private extension VoronoiFrameEncoder {

    struct Uniforms {
        var sizeX: Float
        var sizeY: Float
        var gridSize: Float
        var maxRadius: Float
        var minRadius: Float
        var coordinatesX: Float
        var coordinatesY: Float
    }
}

// MARK: - Exportable

extension Voronoi: VideoExportable {

    func makeFrameEncoder(in context: VideoFrameEncoderContext) throws -> any VideoFrameEncoder {
        try VoronoiFrameEncoder(voronoi: self, context: context)
    }
}
