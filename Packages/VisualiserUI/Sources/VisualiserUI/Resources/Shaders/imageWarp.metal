// Image warp shader — geometric distortion of a SwiftUI layer (photo).
//
// Uses the `runWarp()` domain warp displacement to sample the source layer at
// a displaced position, creating organic geometric distortion. Three modes
// control which pixels are warped: the full image, a radius around the current
// run position, or a band along the entire run path.
//
// Uses layerEffect() rather than colorEffect() so the shader can read neighbouring
// pixels — the photo is sampled at a displaced position instead of just having
// its color transformed in place.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Forward declarations — implemented in warp.metal
struct WarpResult { float f; float2 q; float2 r; };
WarpResult runWarp(float2 p, float octaves, float h, float animTime, float2 flowDir);

// Scales pixel coordinates to noise space.
// A lower value zooms the warp pattern out, showing larger structures.
constant float kNoiseScale = 0.004;

// Maximum pixel displacement at intensity = 1.0.
// Must match the maxSampleOffset constant on the Swift side (ImageWarpView).
constant float kMaxDisplacement = 100.0;

[[ stitchable ]] half4 imageWarpShader(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,              // view size in points
    float time,               // pace-weighted animation clock
    float octaves,            // fBM octave count
    float h,                  // smoothness (H parameter)
    float intensity,          // displacement strength (0–1)
    float mode,               // 0 = full, 1 = position, 2 = path
    float2 coordinates,       // current run position in normalised space (-1, 1)
    float2 direction,         // speed-weighted heading unit vector
    float radius,             // falloff radius in normalised space
    device const void* pathBuffer,
    int pathBytes
) {
    // Isotropic normalised space: both axes divided by the same value (size.y * 0.5)
    // so 1 UV unit = size.y/2 pixels in both x and y, preserving the physical
    // aspect ratio of the run. On a portrait screen this gives x ∈ [-aspect, aspect]
    // and y ∈ [-1, 1] where aspect = size.x / size.y < 1.
    float aspect = size.x / size.y;
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.5 - position.y) / (size.y * 0.5);

    // NormalisedRun coordinates can extend to ±1 on each axis. On a portrait screen
    // the visible x range is only ±aspect ≈ ±0.46, so coordinates with |x| > aspect
    // would be off-screen without adjustment.
    //
    // fitScale maps ±1 run coordinates into the visible UV area while keeping x and
    // y scaled by the same factor — so the run's physical shape is preserved.
    // Portrait: fitScale = aspect → ±1 coords become ±aspect, fitting within the
    //           screen width; y maps to ±aspect ⊂ [-1, 1] (letterboxed vertically).
    // Landscape: fitScale = 1.0 → coords already fit within ±1 (screen height).
    float fitScale = min(1.0, aspect);

    // Noise space UV — maps pixel coordinates into a range where fBM produces
    // interesting large-scale patterns.
    float2 noiseUV = position * kNoiseScale;

    // Compute warp displacement vectors.
    WarpResult w = runWarp(noiseUV, octaves, h, time, direction);

    // Convert noise-space displacement to pixel displacement.
    float2 displacement = (w.q + w.r * 0.5) * intensity * kMaxDisplacement;

    // === MODE MASK ===
    // Controls how much displacement is applied at each pixel.
    // mask = 1.0 → full displacement; mask = 0.0 → undistorted (sample at position).

    float mask;

    if (mode < 0.5) {
        // Full: warp the entire image.
        mask = 1.0;

    } else if (mode < 1.5) {
        // Position: warp within a radius around the current run coordinate.
        // Smoothstep from full warp at the centre to zero at the radius boundary.
        float dist = length(uv - coordinates * fitScale);
        mask = 1.0 - smoothstep(radius * 0.8, radius, dist);

    } else {
        // Path: warp along the run path with a smooth radial falloff.
        // An extra intensity boost is added near the current position.
        device const float2* path = (device const float2*)pathBuffer;
        int pathCount = pathBytes / (int)sizeof(float2);

        float minDist = 1e9;
        for (int i = 1; i < pathCount; i++) {
            float2 a = path[i - 1] * fitScale;
            float2 b = path[i]     * fitScale;
            float2 ab = b - a;
            float t = clamp(dot(uv - a, ab) / dot(ab, ab), 0.0, 1.0);
            float2 closest = a + t * ab;
            minDist = min(minDist, length(uv - closest));
        }

        float pathMask = 1.0 - smoothstep(radius * 0.8, radius, minDist);

        // Boost warp intensity near the current position along the path.
        float posDist = length(uv - coordinates * fitScale);
        float posBoost = (1.0 - smoothstep(0.0, radius * 0.5, posDist)) * 0.5;

        mask = clamp(pathMask + posBoost, 0.0, 1.0);
    }

    // Compute the displaced sample position and clamp to view bounds.
    // Clamping produces a stretched-edge effect at boundaries rather than
    // transparent gaps, which is more aesthetically pleasing for photo warp.
    float2 samplePos = position + displacement * mask;
    samplePos = clamp(samplePos, float2(0.5), size - float2(0.5));

    return layer.sample(samplePos);
}
