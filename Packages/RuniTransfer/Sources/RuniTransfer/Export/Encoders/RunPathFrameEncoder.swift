import CoreGraphics
import Metal
import VisualiserUI

/// Encodes video frames of the `RunPath` visualisation.
///
/// The path is simplified once for the overview zoom level and uploaded
/// as a buffer; each frame only updates the runner's state.
///
struct RunPathFrameEncoder: VideoFrameEncoder {

    let fragmentFunction = "export_path_warp_fragment"

    private let logicalSize: CGSize

    private let pathBuffer: MTLBuffer?

    private let pathCount: Int32

    init(context: VideoFrameEncoderContext) {
        let path = Self.simplified(context.path, logicalSize: context.logicalSize)
        self.logicalSize = context.logicalSize
        self.pathBuffer = Self.makeBuffer(device: context.device, path: path)
        self.pathCount = pathBuffer == nil ? 0 : Int32(path.count)
    }

    func encode(_ state: VisualiserState, into encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms(
            time: state.time,
            sizeX: Float(logicalSize.width),
            sizeY: Float(logicalSize.height),
            scale: 2.0,
            offsetX: 0,
            offsetY: 0,
            coordinatesX: state.coordinates.x,
            coordinatesY: state.coordinates.y,
            directionX: state.direction.x,
            directionY: state.direction.y,
            elevation: state.elevation,
            heartRate: state.heartRate,
            speed: state.speed
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 0)

        if let pathBuffer {
            encoder.setFragmentBuffer(pathBuffer, offset: 0, index: 1)
        }
        var count = pathCount
        encoder.setFragmentBytes(&count, length: MemoryLayout<Int32>.size, index: 2)
    }

    // MARK: - Private

    private static func simplified(_ path: [SIMD2<Float>], logicalSize: CGSize) -> [SIMD2<Float>] {
        guard path.count > 1 else { return [] }
        let overviewEpsilon = Float(2.0 * 10.0 / (logicalSize.height / 2.0))
        let indices = PathSimplifier.rdp(path, epsilon: overviewEpsilon)
        return path.enumerated().compactMap { indices.contains($0.offset) ? $0.element : nil }
    }

    private static func makeBuffer(device: MTLDevice, path: [SIMD2<Float>]) -> MTLBuffer? {
        guard !path.isEmpty else { return nil }
        return device.makeBuffer(
            bytes: path,
            length: path.count * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )
    }
}

// MARK: - Uniforms (must match `PathUniforms` in export.metal)

private extension RunPathFrameEncoder {

    struct Uniforms {
        var time: Float
        var sizeX: Float
        var sizeY: Float
        var scale: Float
        var offsetX: Float
        var offsetY: Float
        var coordinatesX: Float
        var coordinatesY: Float
        var directionX: Float
        var directionY: Float
        var elevation: Float
        var heartRate: Float
        var speed: Float
    }
}

// MARK: - Exportable

extension RunPath: VideoExportable {

    func makeFrameEncoder(in context: VideoFrameEncoderContext) throws -> any VideoFrameEncoder {
        RunPathFrameEncoder(context: context)
    }
}
