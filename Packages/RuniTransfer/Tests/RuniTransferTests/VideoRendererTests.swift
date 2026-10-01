import AVFoundation
import CoreGraphics
import CoreKit
import Foundation
import ImageIO
import RunKit
import Testing
import UniformTypeIdentifiers
import VisualiserUI
@testable import RuniTransfer

/// Renders short clips through the real Metal + video writer pipeline and
/// inspects the decoded frames.
///
/// Two synthetic photos are used by the photo-based visualisations:
/// - a photo of four flat-coloured quadrants, to check which part of the photo
///   ends up where in the frame;
/// - a photo of small randomly coloured tiles, where every voronoi cell picks up
///   its own colour, to check how dense the cells are in a region of the frame.
///
struct VideoRendererTests {

    /// Frame of the clip that is inspected.
    private let inspectedFrame = 5

    private let fps = 10

    private let size = CGSize(width: 320, height: 240)

    // MARK: - Voronoi

    @Test func voronoiRendersThePhoto() async throws {
        let frame = try await renderedFrame(of: Voronoi(), photo: quadrantPhoto(), named: "voronoi-fixed")

        #expect(frame.quadrantColor(atX: 0.25, y: 0.25) == .topLeft)
        #expect(frame.quadrantColor(atX: 0.75, y: 0.25) == .topRight)
        #expect(frame.quadrantColor(atX: 0.25, y: 0.75) == .bottomLeft)
        #expect(frame.quadrantColor(atX: 0.75, y: 0.75) == .bottomRight)
    }

    @Test func voronoiAspectFillsThePhoto() async throws {
        // A photo wider than the canvas is cropped at the sides, so the
        // quadrant boundary stays in the centre of the frame.
        let photo = quadrantPhoto(width: 800, height: 300)
        let frame = try await renderedFrame(of: Voronoi(), photo: photo, named: "voronoi-wide-photo")

        #expect(frame.quadrantColor(atX: 0.25, y: 0.25) == .topLeft)
        #expect(frame.quadrantColor(atX: 0.75, y: 0.25) == .topRight)
        #expect(frame.quadrantColor(atX: 0.25, y: 0.75) == .bottomLeft)
        #expect(frame.quadrantColor(atX: 0.75, y: 0.75) == .bottomRight)
    }

    @Test func voronoiIsDenserAroundTheRunner() async throws {
        let frame = try await renderedFrame(of: Voronoi(), photo: tiledPhoto(), named: "voronoi-density")
        let runner = runnerPosition()

        let nearby = frame.distinctColors(around: runner, radius: 24)
        let faraway = frame.distinctColors(around: farthestCorner(from: runner, inset: 24), radius: 24)

        #expect(nearby > faraway * 2)
    }

    @Test func dynamicVoronoiRendersThePhoto() async throws {
        let frame = try await renderedFrame(of: Voronoi(mode: .dynamic), photo: tiledPhoto(), named: "voronoi-dynamic")
        let runner = runnerPosition()

        let nearby = frame.distinctColors(around: runner, radius: 24)
        let faraway = frame.distinctColors(around: farthestCorner(from: runner, inset: 24), radius: 24)

        #expect(nearby > faraway)
    }

    @Test func voronoiWithoutPhotoFails() async throws {
        await #expect {
            try await render(Voronoi(), photo: nil)
        } throws: { error in
            guard case VideoRenderer.RenderError.photoMissing = error else { return false }
            return true
        }
    }

    @Test func voronoiWithUnreadablePhotoFails() async throws {
        await #expect {
            try await render(Voronoi(), photo: Data([0, 1, 2, 3]))
        } throws: { error in
            guard case VideoRenderer.RenderError.photoUnreadable = error else { return false }
            return true
        }
    }

    // MARK: - Other Visualisations

    @Test func warpStillRenders() async throws {
        let frame = try await renderedFrame(of: Warp(), photo: nil, named: "warp")

        #expect(frame.hasVisibleContent)
    }

    @Test func runPathStillRenders() async throws {
        let frame = try await renderedFrame(of: RunPath(), photo: nil, named: "run-path")

        #expect(frame.hasVisibleContent)
    }

    @Test func unsupportedVisualisationFails() async throws {
        await #expect {
            try await render(Gradients(), photo: nil)
        } throws: { error in
            guard case VideoRenderer.RenderError.unsupportedVisualisation = error else { return false }
            return true
        }
    }

    // MARK: - Rendering

    @discardableResult
    private func render(_ visualisation: any Visualisation, photo: Data?) async throws -> URL {
        try await VideoRenderer().render(
            run: run(),
            duration: 1,
            config: VideoExportConfig(resolution: size, fps: fps, photo: photo),
            visualisation: visualisation,
            onProgress: { _ in }
        )
    }

    /// Renders a clip and returns the inspected frame, also saved
    /// as a PNG in the temporary directory for visual inspection.
    ///
    private func renderedFrame(
        of visualisation: any Visualisation,
        photo: Data?,
        named name: String
    ) async throws -> Frame {
        let url = try await render(visualisation, photo: photo)
        defer { try? FileManager.default.removeItem(at: url) }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(value: CMTimeValue(inspectedFrame), timescale: CMTimeScale(fps))
        let image = try await generator.image(at: time).image

        save(image, named: name)
        return Frame(image: image)
    }

    private func save(_ image: CGImage, named name: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("runi-export-tests")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Runner

    /// Position of the runner in the inspected frame, in pixels with a top-left origin.
    ///
    /// Mirrors the mapping of the voronoi shader: run coordinates are y-up and
    /// span ±1 across the short side of the canvas.
    ///
    private func runnerPosition() -> CGPoint {
        let segments = run().segments
        let progress = Double(inspectedFrame) / Double(fps - 1)
        let segment = segments[min(Int(progress * Double(segments.count)), segments.count - 1)]
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: (segment.coordinate.x * minSide + size.width) / 2,
            y: (-segment.coordinate.y * minSide + size.height) / 2
        )
    }

    private func farthestCorner(from point: CGPoint, inset: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x < size.width / 2 ? size.width - inset : inset,
            y: point.y < size.height / 2 ? size.height - inset : inset
        )
    }

    // MARK: - Fixtures

    /// A short run heading north-east with rising heart rate and varying pace,
    /// processed the same way `ExportVideoAction` does.
    ///
    private func run() -> Run {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let points = (0..<20).map { index in
            let step = Double(index)
            return GPX.Point(
                cadence: 170,
                elevation: 10 + step,
                heartRate: 120 + index * 3,
                latitude: 51.5 + step * step * 0.00002,
                longitude: -0.12 + step * 0.0004,
                time: start.addingTimeInterval(step * 10)
            )
        }
        return Run.Parser()
            .run(from: GPX.Track(name: "Test", points: points))
            .transform(by: .normalised)
            .interpolate(by: .linear, with: RunPlayer.Timing(duration: 1, fps: 30))
    }

    /// PNG bytes of a photo split into four flat-coloured quadrants.
    ///
    private func quadrantPhoto(width: Int = 400, height: Int = 300) -> Data {
        let context = bitmap(width: width, height: height)
        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2

        // Core Graphics draws with a bottom-left origin.
        fill(.topLeft, in: CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight), of: context)
        fill(.topRight, in: CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight), of: context)
        fill(.bottomLeft, in: CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), of: context)
        fill(.bottomRight, in: CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight), of: context)

        return pngData(of: context)
    }

    /// PNG bytes of a photo made of small tiles with pseudo-random colours,
    /// so neighbouring voronoi cells pick up clearly different colours.
    ///
    private func tiledPhoto(width: Int = 640, height: Int = 480, tile: Int = 4) -> Data {
        let context = bitmap(width: width, height: height)
        for row in 0..<(height / tile) {
            for column in 0..<(width / tile) {
                let rect = CGRect(x: column * tile, y: row * tile, width: tile, height: tile)
                fill(tileColor(row: row, column: column), in: rect, of: context)
            }
        }
        return pngData(of: context)
    }

    private func tileColor(row: Int, column: Int) -> Frame.Color {
        var hash = UInt32(truncatingIfNeeded: row &* 73_856_093 ^ column &* 19_349_663)
        hash ^= hash >> 13
        hash = hash &* 0x5bd1_e995
        hash ^= hash >> 15
        return Frame.Color(
            red: Int(hash & 0xff),
            green: Int((hash >> 8) & 0xff),
            blue: Int((hash >> 16) & 0xff)
        )
    }

    private func bitmap(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private func pngData(of context: CGContext) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func fill(_ color: Frame.Color, in rect: CGRect, of context: CGContext) {
        context.setFillColor(
            red: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
        context.fill(rect)
    }
}

// MARK: - Frame

/// A decoded video frame whose pixels can be sampled.
///
private struct Frame {

    struct Color: Hashable {
        let red: Int
        let green: Int
        let blue: Int

        /// Squared distance of the colours in RGB space.
        func distance(to other: Color) -> Int {
            let red = red - other.red
            let green = green - other.green
            let blue = blue - other.blue
            return red * red + green * green + blue * blue
        }

        /// The colour rounded to coarse steps, absorbing video compression noise.
        var quantised: Color {
            Color(red: red / 32, green: green / 32, blue: blue / 32)
        }
    }

    private let bytes: [UInt8]

    private let height: Int

    private let width: Int

    init(image: CGImage) {
        width = image.width
        height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        self.bytes = bytes
    }

    /// Whether the frame is more than a flat black canvas.
    var hasVisibleContent: Bool {
        stride(from: 0, to: bytes.count, by: 4).contains { index in
            bytes[index] > 24 || bytes[index + 1] > 24 || bytes[index + 2] > 24
        }
    }

    /// The quadrant colour closest to the pixel at the given position,
    /// in unit coordinates with a top-left origin.
    ///
    /// Matching the closest colour rather than an exact one absorbs the
    /// colour shift of the video codec.
    ///
    func quadrantColor(atX x: Double, y: Double) -> Color {
        let color = color(column: Int(x * Double(width)), row: Int(y * Double(height)))
        return Color.quadrants.min { $0.distance(to: color) < $1.distance(to: color) }!
    }

    /// Number of clearly different colours in the square around the given pixel position.
    func distinctColors(around center: CGPoint, radius: Int) -> Int {
        var colors = Set<Color>()
        for row in (Int(center.y) - radius)...(Int(center.y) + radius) {
            for column in (Int(center.x) - radius)...(Int(center.x) + radius) {
                colors.insert(color(column: column, row: row).quantised)
            }
        }
        return colors.count
    }

    // MARK: - Private

    private func color(column: Int, row: Int) -> Color {
        let column = max(0, min(width - 1, column))
        let row = max(0, min(height - 1, row))
        let index = (row * width + column) * 4
        return Color(red: Int(bytes[index]), green: Int(bytes[index + 1]), blue: Int(bytes[index + 2]))
    }
}

// MARK: - Quadrant Colours

private extension Frame.Color {

    static let topLeft = Frame.Color(red: 220, green: 40, blue: 40)

    static let topRight = Frame.Color(red: 40, green: 200, blue: 60)

    static let bottomLeft = Frame.Color(red: 40, green: 60, blue: 220)

    static let bottomRight = Frame.Color(red: 230, green: 210, blue: 40)

    static let quadrants: [Frame.Color] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
