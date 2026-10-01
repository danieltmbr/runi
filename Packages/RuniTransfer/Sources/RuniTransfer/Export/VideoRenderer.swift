import AVFoundation
import CoreGraphics
import CoreVideo
import Metal
import RunKit
import VisualiserUI

/// Renders a Runimation visualisation to an `.mp4` file using a raw Metal pipeline.
///
/// Each frame is rendered independently — progress is looked up via the pre-processed
/// segment array rather than running at real-time playback speed. A 2-minute
/// animation at 30 fps (3600 frames) typically takes 30–60 seconds to render.
///
/// The export pipeline uses dedicated Metal shaders (`export.metal`) compiled into
/// `Bundle.visualiserUI`. These mirror the live stitchable shaders but use standard
/// vertex + fragment functions rather than SwiftUI's `[[stitchable]]` calling
/// convention, allowing them to be driven via a plain `MTLRenderCommandEncoder`.
///
/// The renderer owns what all visualisations share: the Metal device, the render
/// target and the video writer. What differs per visualisation — the fragment
/// function and its uniforms, buffers and textures — is delegated to the
/// `VideoFrameEncoder` the visualisation provides through `VideoExportable`.
///
public struct VideoRenderer {

    public init() {}

    // MARK: - Errors

    public enum RenderError: LocalizedError {
        case noMetalDevice
        case metalLibraryNotFound
        case photoMissing
        case photoUnreadable
        case setupFailed(String)
        case unsupportedVisualisation(String)
        case writeFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .noMetalDevice:           return "No Metal device available."
            case .metalLibraryNotFound:    return "Export Metal library not found in Visualiser bundle."
            case .photoMissing:            return "No photo is selected. Choose a photo for the visualisation first."
            case .photoUnreadable:         return "The selected photo could not be read."
            case .setupFailed(let msg):    return "Export setup failed: \(msg)"
            case .unsupportedVisualisation(let label):
                return "Video export is not supported for the \(label) visualisation yet."
            case .writeFailed(let error):  return "Video write failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Render

    /// Renders every frame to disk and returns the URL of the resulting `.mp4` file.
    ///
    /// - Parameter run: The normalised and interpolated run that drives the animation.
    ///
    public func render(
        run: Run,
        duration: TimeInterval,
        config: VideoExportConfig,
        visualisation: any Visualisation,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {

        let fps = config.fps
        let totalFrames = max(1, Int(duration * Double(fps)))
        let width = Int(config.resolution.width)
        let height = Int(config.resolution.height)
        let path = run.coordinates.map { SIMD2<Float>(Float($0.x), Float($0.y)) }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RenderError.setupFailed("Could not create command queue")
        }

        let frameEncoder = try makeFrameEncoder(
            for: visualisation,
            context: VideoFrameEncoderContext(
                device: device,
                logicalSize: config.logicalSize,
                resolution: config.resolution,
                path: path,
                photo: config.photo
            )
        )

        guard let metalLibURL = Bundle.visualiserUI.url(forResource: "default", withExtension: "metallib") else {
            throw RenderError.metalLibraryNotFound
        }
        let library = try device.makeLibrary(URL: metalLibURL)

        let (vertexFunction, fragmentFunction) = try shaderFunctions(library: library, fragmentName: frameEncoder.fragmentFunction)
        let pipeline = try makePipeline(device: device, vertex: vertexFunction, fragment: fragmentFunction)

        let renderTexture = try makeRenderTexture(device: device, width: width, height: height)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: config.codec.rawValue,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 30_000_000,
                AVVideoMaxKeyFrameIntervalKey: config.fps,
                AVVideoExpectedSourceFrameRateKey: config.fps
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for i in 0..<totalFrames {
            let progress = totalFrames > 1 ? Double(i) / Double(totalFrames - 1) : 0.0

            let pixelBuffer = try await renderFrame(
                commandQueue: commandQueue,
                pipeline: pipeline,
                renderTexture: renderTexture,
                frameEncoder: frameEncoder,
                state: state(of: run, path: path, at: progress, duration: duration)
            )

            let presentationTime = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            await MainActor.run { onProgress(Double(i + 1) / Double(totalFrames)) }
        }

        writerInput.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        if let error = writer.error { throw RenderError.writeFailed(error) }

        return outputURL
    }

    // MARK: - Frame Rendering

    private func renderFrame(
        commandQueue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState,
        renderTexture: MTLTexture,
        frameEncoder: any VideoFrameEncoder,
        state: VisualiserState
    ) async throws -> CVPixelBuffer {

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RenderError.setupFailed("Could not create command buffer")
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = renderTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw RenderError.setupFailed("Could not create render encoder")
        }
        encoder.setRenderPipelineState(pipeline)
        frameEncoder.encode(state, into: encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            commandBuffer.commit()
        }

        return try readbackPixelBuffer(from: renderTexture)
    }

    /// Builds the state the visualisation sees at the given playback progress,
    /// mirroring what the app feeds to the live canvas.
    ///
    private func state(
        of run: Run,
        path: [SIMD2<Float>],
        at progress: Double,
        duration: TimeInterval
    ) -> VisualiserState {
        let segments = run.segments
        let segment = segments.isEmpty ? Run.Segment.zero : segments[segmentIndex(at: progress, count: segments.count)]
        return VisualiserState(
            averageHeartRate: Float(run.averages.heartRate),
            averageSpeed: Float(run.averages.speed),
            coordinates: SIMD2(Float(segment.coordinate.x), Float(segment.coordinate.y)),
            direction: SIMD2(Float(segment.direction.x), Float(segment.direction.y)),
            elevation: Float(segment.elevation),
            heartRate: Float(segment.heartRate),
            path: path,
            speed: Float(segment.speed),
            time: Float(progress * duration)
        )
    }

    // MARK: - Texture Readback

    private func readbackPixelBuffer(from texture: MTLTexture) throws -> CVPixelBuffer {
        let width = texture.width
        let height = texture.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw RenderError.setupFailed("Could not create CVPixelBuffer")
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else {
            throw RenderError.setupFailed("Could not get pixel buffer base address")
        }

        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOriginMake(0, 0, 0), size: MTLSizeMake(width, height, 1)),
            mipmapLevel: 0
        )
        return pb
    }

    // MARK: - Setup Helpers

    private func makeFrameEncoder(
        for visualisation: any Visualisation,
        context: VideoFrameEncoderContext
    ) throws -> any VideoFrameEncoder {
        guard let exportable = visualisation as? any VideoExportable else {
            throw RenderError.unsupportedVisualisation(visualisation.label)
        }
        return try exportable.makeFrameEncoder(in: context)
    }

    private func shaderFunctions(library: MTLLibrary, fragmentName: String) throws -> (MTLFunction, MTLFunction) {
        guard let vertex = library.makeFunction(name: "export_vertex") else {
            throw RenderError.setupFailed("export_vertex shader not found")
        }
        guard let fragment = library.makeFunction(name: fragmentName) else {
            throw RenderError.setupFailed("\(fragmentName) shader not found")
        }
        return (vertex, fragment)
    }

    private func makePipeline(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeRenderTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderError.setupFailed("Could not create render texture")
        }
        return texture
    }

    private func segmentIndex(at progress: Double, count: Int) -> Int {
        min(Int(progress * Double(count)), count - 1)
    }
}
