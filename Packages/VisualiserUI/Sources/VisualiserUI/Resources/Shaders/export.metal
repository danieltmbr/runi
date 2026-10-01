// Export shaders — standard Metal vertex + fragment pipeline for offline video rendering.
//
// These shaders mirror the logic in run.metal but use a uniform buffer instead of
// SwiftUI's [[stitchable]] calling convention, so they can be driven by a plain
// MTLRenderCommandEncoder without the SwiftUI rasterization layer.
//
// Math functions (hash, noised, fbm, runWarp, WarpResult) are implemented in the
// other .metal files of this package and resolved at link time via forward declarations.

#include <metal_stdlib>
using namespace metal;

// Forward declarations — implemented in noise.metal, fbm.metal, run.metal
float3 noised(float2 position);
float  fbm(float2 position, float octaves, float h);

struct WarpResult { float f; float2 q; float2 r; };
WarpResult runWarp(float2 p, float octaves, float h, float animTime, float2 flowDir);

// Forward declaration — implemented in voronoi.metal
float2 dynamicDensityVoronoiFeature(float2 uv, float gridSize, float maxRadius, float minRadius, float2 focus);

// ============================================================
// Vertex shader — full-screen triangle, no vertex buffer needed
// ============================================================

struct ExportVertex {
    float4 position [[position]];
    float2 uv;
};

vertex ExportVertex export_vertex(uint vertexID [[vertex_id]]) {
    // Three vertices that cover the entire clip space.
    // NDC y=1 → uv.y=0 (top), NDC y=-1 → uv.y=1 (bottom) — same top-left origin as screen coords.
    float2 positions[3] = {
        float2(-1.0, -3.0),
        float2(-1.0,  1.0),
        float2( 3.0,  1.0)
    };
    float2 pos = positions[vertexID];
    ExportVertex out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2((pos.x + 1.0) * 0.5, (1.0 - pos.y) * 0.5);
    return out;
}

// ============================================================
// Warp fragment shader — mirrors runWarpShader from run.metal
// ============================================================

struct WarpUniforms {
    float time;
    float octaves;
    float h;
    float scale;
    float speed;
    float heartRate;
    float dirX;
    float dirY;
    float offsetX;
    float offsetY;
    float sizeX;
    float sizeY;
};

fragment half4 export_warp_fragment(
    ExportVertex in [[stage_in]],
    constant WarpUniforms& u [[buffer(0)]],
    texture2d<half, access::sample> palette [[texture(0)]]
) {
    float2 position = float2(in.uv.x * u.sizeX, in.uv.y * u.sizeY);
    float2 uv = position * u.scale + float2(u.offsetX, u.offsetY);

    float breathRate = 0.3 + u.heartRate * 0.8;
    float breath = sin(u.time * breathRate) * 0.5 + 0.5;
    float animH = clamp(u.h + breath * 0.2 - 0.1, 0.0, 1.0);
    float2 flowDir = float2(u.dirX, u.dirY);

    WarpResult w = runWarp(uv, u.octaves, animH, u.time, flowDir);
    float f = w.f * 0.5 + 0.5;
    float2 q = w.q;
    float2 r = w.r;

    constexpr sampler paletteSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float warpMag = clamp(length(q) * 0.5 + length(r) * 0.3, 0.0, 1.0);
    float pu = clamp(warpMag * 0.8 + u.heartRate * 0.2, 0.0, 1.0);
    float3 c = float3(palette.sample(paletteSampler, float2(pu, 0.5)).rgb);

    float rStrength = clamp(dot(r, r) * (0.2 + u.heartRate * 0.3), 0.0, 1.0);
    float3 highlight = mix(float3(0.9, 0.95, 1.0), float3(1.0, 0.85, 0.7), u.heartRate);
    c = mix(c, highlight, rStrength);

    float edges = smoothstep(0.8, 1.2, abs(r.x) + abs(r.y));
    float3 edgeColor = mix(float3(0.1, 0.4, 0.5), float3(0.5, 0.2, 0.1), u.heartRate);
    c = mix(c, edgeColor, edges * (0.2 + u.speed * 0.2));

    c *= 0.7 + 0.3 * f;
    c += sin(u.time * breathRate * 0.5) * 0.04;

    return half4(half3(clamp(c, 0.0, 1.0)), 1.0);
}

// ============================================================
// Path fragment shaders — mirror runPathShader / runPathWarpShader
// ============================================================

struct PathUniforms {
    float time;
    float sizeX;
    float sizeY;
    float scale;
    float offsetX;
    float offsetY;
    float coordinatesX;
    float coordinatesY;
    float directionX;
    float directionY;
    float elevation;
    float heartRate;
    float speed;
};

fragment half4 export_path_fragment(
    ExportVertex in [[stage_in]],
    constant PathUniforms& u [[buffer(0)]],
    device const float2* path [[buffer(1)]],
    constant int& pathCount [[buffer(2)]]
) {
    float2 position = float2(in.uv.x * u.sizeX, in.uv.y * u.sizeY);
    float2 size = float2(u.sizeX, u.sizeY);
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.5 - position.y) / (size.y * 0.5) * u.scale + float2(u.offsetX, u.offsetY);

    float minDist = 1e9;
    for (int i = 1; i < pathCount; i++) {
        float2 a = path[i - 1];
        float2 b = path[i];
        float2 ab = b - a;
        float t = clamp(dot(uv - a, ab) / dot(ab, ab), 0.0, 1.0);
        minDist = min(minDist, length(uv - (a + t * ab)));
    }

    float line = 1.0 - smoothstep(0.0, 0.01, minDist);
    float3 color = float3(line);

    float2 coords = float2(u.coordinatesX, u.coordinatesY);
    float circleDiameter = 0.03;
    float outerCircleDiameter = 0.045 + 0.015 * (cos(u.time * 2) * cos(u.time * 2));
    if (length(coords - uv) < outerCircleDiameter) { color = float3(0.18, 0.44, 0.93) * 0.5; }
    if (length(coords - uv) < circleDiameter)      { color = float3(0.18, 0.44, 0.93); }

    return half4(half3(color), 1.0);
}

fragment half4 export_path_warp_fragment(
    ExportVertex in [[stage_in]],
    constant PathUniforms& u [[buffer(0)]],
    device const float2* path [[buffer(1)]],
    constant int& pathCount [[buffer(2)]]
) {
    float2 position = float2(in.uv.x * u.sizeX, in.uv.y * u.sizeY);
    float2 size = float2(u.sizeX, u.sizeY);
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.5 - position.y) / (size.y * 0.5) * u.scale + float2(u.offsetX, u.offsetY);

    float2 dir = float2(u.directionX, u.directionY);
    WarpResult w = runWarp(uv, 5, 0.94, u.time, dir);
    float2 q = w.q;
    float2 r = w.r;
    uv += q * 0.17;

    float minDist = 1e9;
    for (int i = 1; i < pathCount; i++) {
        float2 a = path[i - 1];
        float2 b = path[i];
        float2 ab = b - a;
        float t = clamp(dot(uv - a, ab) / dot(ab, ab), 0.0, 1.0);
        minDist = min(minDist, length(uv - (a + t * ab)));
    }

    float2 coords = float2(u.coordinatesX, u.coordinatesY);
    float cd = length(coords - uv);
    float lineWidth = 0.01 + 0.005 * length(r) + 0.12 * (1.0 - smoothstep(0.0, 0.25, abs(cd)));
    float line = 1.0 - smoothstep(0.0, lineWidth, minDist);
    float3 color = float3(line);

    float circleDiameter = 0.03;
    float outerCircleDiameter = 0.045 + 0.015 * (cos(u.time * 2) * cos(u.time * 2));

    float2 cd1pos = uv + sin(u.time - r) * circleDiameter;
    float2 cd2pos = uv + sin(u.time + M_PI_F + r) * circleDiameter;

    circleDiameter      += 0.01 * length(r);
    outerCircleDiameter += 0.01 * length(r);

    if (length(coords - cd1pos) < outerCircleDiameter) { color = float3(0.18, 0.44, 0.93) * 0.5; }
    if (length(coords - cd1pos) < circleDiameter)      { color = float3(0.18, 0.44, 0.93); }
    if (length(coords - cd2pos) < outerCircleDiameter) { color = float3(1.0, 0.22, 0.23) * 0.5; }
    if (length(coords - cd2pos) < circleDiameter)      { color = float3(1.0, 0.22, 0.23); }

    return half4(half3(color), 1.0);
}

// ============================================================
// Voronoi fragment shader — mirrors dynamicDensityVoronoi from voronoi.metal
// ============================================================

struct VoronoiUniforms {
    float sizeX;
    float sizeY;
    float gridSize;
    float maxRadius;
    float minRadius;
    float coordinatesX;
    float coordinatesY;
};

// `photo` is expected to be pre-rendered aspect-filled to the viewport, so it
// covers the canvas exactly like the SwiftUI layer the live shader samples.
fragment half4 export_voronoi_fragment(
    ExportVertex in [[stage_in]],
    constant VoronoiUniforms& u [[buffer(0)]],
    texture2d<half, access::sample> photo [[texture(0)]]
) {
    float2 size = float2(u.sizeX, u.sizeY);
    float2 position = in.uv * size;
    float minSide = min(size.x, size.y);

    float2 uv = (2.0 * position - size) / minSide;

    // Run coordinates are y-up while uv is y-down, so flip the vertical axis.
    float2 focus = float2(u.coordinatesX, -u.coordinatesY);

    float2 sampleUV = dynamicDensityVoronoiFeature(uv, u.gridSize, u.maxRadius, u.minRadius, focus);
    float2 samplePosition = (sampleUV * minSide + size) * 0.5;

    // Edge cells can have their feature point off-screen; clamp so they sample
    // the nearest edge pixel instead of reading outside the photo bounds.
    samplePosition = clamp(samplePosition, float2(0.5), size - float2(0.5));

    constexpr sampler photoSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return half4(photo.sample(photoSampler, samplePosition / size).rgb, 1.0);
}
