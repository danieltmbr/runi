import CoreGraphics
import Foundation
import simd
import SwiftUI

/// A rasterised map of how far every point of the canvas is from the run path.
///
/// Shaders that let the path influence their geometry need the path distance of
/// arbitrary points, many times per pixel. Searching the path each time is far
/// too expensive, so the distance is computed once on the CPU into a small
/// texture and sampled in the shader with a single texture read.
///
/// The field covers the square `[-extent, extent]²` of the shader's uv space
/// (aspect preserving, y down, ±1 on the short side of the canvas). Each texel
/// stores `min(distance / maxDistance, 1)`, so the shader reconstructs the
/// distance in uv units as `sample * maxDistance`.
///
struct PathDistanceField {

    /// Half the side of the uv square the field covers. Chosen so that any cell
    /// within the largest density radius of a point of the path stays inside the field.
    static let extent: Float = 2.5

    /// Distance encoded as 1.0. Anything farther is clamped, which is harmless
    /// because it is beyond any density radius.
    static let maxDistance: Float = 2.0

    /// Grayscale texture to pass to the shader as an `.image(_:)` argument.
    let image: Image

    /// A field with no path: every texel reads as `maxDistance`.
    static let empty = PathDistanceField(cgImage: PathDistanceFieldRenderer.emptyImage())

    init(cgImage: CGImage) {
        #if os(macOS)
        image = Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        #else
        image = Image(uiImage: UIImage(cgImage: cgImage))
        #endif
    }
}

// MARK: - Renderer

/// Rasterises a run path into the texture of a `PathDistanceField`.
///
/// The path is drawn onto a grid, then an exact Euclidean distance transform
/// (Felzenszwalb & Huttenlocher) spreads the distances over the whole grid.
/// The cost depends on the grid size only, not on the length of the path.
///
struct PathDistanceFieldRenderer: Sendable {

    /// Texels per side of the square field.
    let resolution: Int

    init(resolution: Int = 256) {
        self.resolution = resolution
    }

    /// Renders the field of the given path, given as normalised run coordinates (y up).
    ///
    func render(_ path: [SIMD2<Float>]) -> CGImage {
        var squaredTexelDistances = rasterised(path)
        distanceTransform(&squaredTexelDistances)
        return image(from: encoded(squaredTexelDistances))
    }

    /// A 1×1 field reading as `maxDistance` everywhere.
    ///
    static func emptyImage() -> CGImage {
        PathDistanceFieldRenderer(resolution: 1).image(from: [255])
    }

    // MARK: - Private

    private var texelSize: Float {
        2 * PathDistanceField.extent / Float(resolution)
    }

    /// Returns a grid holding 0 on texels the path passes through and "infinity" elsewhere.
    ///
    private func rasterised(_ path: [SIMD2<Float>]) -> [Float] {
        var grid = [Float](repeating: Self.infinity, count: resolution * resolution)
        guard path.count > 1 else { return grid }

        for index in 1..<path.count {
            let start = texelPosition(of: path[index - 1])
            let end = texelPosition(of: path[index])
            let steps = max(1, Int((simd_length(end - start) * 2).rounded(.up)))
            for step in 0...steps {
                let position = start + (end - start) * (Float(step) / Float(steps))
                mark(position, in: &grid)
            }
        }
        return grid
    }

    /// Maps a normalised run coordinate (y up) to the texel grid of the uv square (y down).
    ///
    private func texelPosition(of coordinate: SIMD2<Float>) -> SIMD2<Float> {
        let uv = SIMD2(coordinate.x, -coordinate.y)
        return (uv + PathDistanceField.extent) / texelSize - 0.5
    }

    private func mark(_ position: SIMD2<Float>, in grid: inout [Float]) {
        let column = Int(position.x.rounded())
        let row = Int(position.y.rounded())
        guard (0..<resolution).contains(column), (0..<resolution).contains(row) else { return }
        grid[row * resolution + column] = 0
    }

    /// Replaces the grid in place with the squared distance (in texels) to the nearest marked texel.
    ///
    private func distanceTransform(_ grid: inout [Float]) {
        var line = [Float](repeating: 0, count: resolution)
        var transformed = [Float](repeating: 0, count: resolution)

        for column in 0..<resolution {
            for row in 0..<resolution { line[row] = grid[row * resolution + column] }
            distanceTransform(line, into: &transformed)
            for row in 0..<resolution { grid[row * resolution + column] = transformed[row] }
        }
        for row in 0..<resolution {
            let start = row * resolution
            for column in 0..<resolution { line[column] = grid[start + column] }
            distanceTransform(line, into: &transformed)
            for column in 0..<resolution { grid[start + column] = transformed[column] }
        }
    }

    /// One-dimensional squared distance transform of `f` (lower envelope of parabolas).
    ///
    private func distanceTransform(_ f: [Float], into d: inout [Float]) {
        let n = f.count
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = 0
        z[0] = -Self.infinity
        z[1] = Self.infinity

        for q in 1..<n {
            var s = intersection(f, q, v[k])
            while s <= z[k] {
                k -= 1
                s = intersection(f, q, v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = Self.infinity
        }

        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let offset = Float(q - v[k])
            d[q] = offset * offset + f[v[k]]
        }
    }

    /// Horizontal position where the parabolas rooted at `q` and `p` intersect.
    private func intersection(_ f: [Float], _ q: Int, _ p: Int) -> Float {
        let fq = f[q] + Float(q * q)
        let fp = f[p] + Float(p * p)
        return (fq - fp) / Float(2 * q - 2 * p)
    }

    /// Encodes squared texel distances as bytes of `min(distance / maxDistance, 1)`.
    ///
    private func encoded(_ squaredTexelDistances: [Float]) -> [UInt8] {
        let scale = texelSize / PathDistanceField.maxDistance
        return squaredTexelDistances.map { squared in
            UInt8((min(1, squared.squareRoot() * scale) * 255).rounded())
        }
    }

    private func image(from bytes: [UInt8]) -> CGImage {
        let side = Int(Double(bytes.count).squareRoot())
        let data = Data(bytes) as CFData
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: data)!,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    /// Large finite stand-in for infinity: keeps the parabola intersections free
    /// of NaN, yet small enough that `Float` still resolves `infinity + q²`.
    private static let infinity: Float = 1e8
}
