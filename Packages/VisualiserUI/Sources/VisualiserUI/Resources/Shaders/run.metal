#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Forward declarations — implemented in warp.metal and fbm.metal
struct WarpResult { float f; float2 q; float2 r; };
float fbm(float2 position, float octaves, float h);
WarpResult runWarp(float2 p, float octaves, float h, float animTime, float2 flowDir);

[[ stitchable ]] half4 runWarpShader(
                                     float2 position,
                                     half4 currentColor,
                                     float time,       // pace-weighted animation time from PlaybackEngine.animationTime
                                     float octaves,
                                     float h,          // from elevation (inverted: high elevation → lower h → rougher)
                                     float scale,      // zoom level
                                     float speed,      // 0..1 normalized speed
                                     float heartRate,  // 0..1 normalized heart rate
                                     float dirX,       // speed-weighted direction X (East+, West-)
                                     float dirY,       // speed-weighted direction Y (North+, South-)
                                     float offsetX,    // noise-space pan offset
                                     float offsetY,
                                     texture2d<half, access::sample> palette [[texture(0)]]
                                     )
{
    float2 uv = position * scale + float2(offsetX, offsetY);

    // === ANIMATION ===

    // Breathing H: HR drives frequency, elevation drives base value via `h`.
    float breathRate = 0.3 + heartRate * 0.8;
    float breath = sin(time * breathRate) * 0.5 + 0.5;
    float animH = clamp(h + breath * 0.2 - 0.1, 0.0, 1.0);

    // flowDir is already speed-weighted from RunData: near-zero at rest,
    // ~unit vector at max running pace. No additional scaling needed.
    float2 flowDir = float2(dirX, dirY);

    // === WARP ===
    WarpResult w = runWarp(uv, octaves, animH, time, flowDir);

    float f = w.f * 0.5 + 0.5;
    float2 q = w.q;
    float2 r = w.r;

    // === COLORING ===
    // Sample the photo-derived palette LUT using warp magnitude as the base UV.
    // Low HR stays near the cool (low-u) region; high HR shifts toward the warm end.
    constexpr sampler paletteSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float warpMag = clamp(length(q) * 0.5 + length(r) * 0.3, 0.0, 1.0);
    float u = clamp(warpMag * 0.8 + heartRate * 0.2, 0.0, 1.0);
    float3 c = float3(palette.sample(paletteSampler, float2(u, 0.5)).rgb);

    float rStrength = clamp(dot(r, r) * (0.2 + heartRate * 0.3), 0.0, 1.0);
    float3 highlight = mix(float3(0.9, 0.95, 1.0), float3(1.0, 0.85, 0.7), heartRate);
    c = mix(c, highlight, rStrength);

    float edges = smoothstep(0.8, 1.2, abs(r.x) + abs(r.y));
    float3 edgeColor = mix(float3(0.1, 0.4, 0.5), float3(0.5, 0.2, 0.1), heartRate);
    c = mix(c, edgeColor, edges * (0.2 + speed * 0.2));

    c *= 0.7 + 0.3 * f;
    c += sin(time * breathRate * 0.5) * 0.04;

    return half4(half3(clamp(c, 0.0, 1.0)), 1.0);
}

[[ stitchable ]] half4 runPathShader(
                                     float2 position,
                                     half4 currentColor,
                                     float time,
                                     float2 size,
                                     float scale,
                                     float2 offset,
                                     float2 coordinates,
                                     float2 direction,
                                     float elevation,
                                     float heartRate,
                                     device const void* pathBuffer,
                                     int pathBytes,
                                     float speed
                                     )
{
    device const float2* path = (device const float2*)pathBuffer;
    int pathCount = pathBytes / sizeof(float2);
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.5 - position.y) / (size.y * 0.5) * scale + offset;
    
    float minDist = 1e9;
    for (int i = 1; i < pathCount; i++) {
        float2 a = path[i - 1];
        float2 b = path[i];
        // project uv onto segment a→b, clamped to [0,1]
        float2 ab = b - a;
        float t = clamp(dot(uv - a, ab) / dot(ab, ab), 0.0, 1.0);
        float2 closest = a + t * ab;
        minDist = min(minDist, length(uv - closest));
    }
    
    float lineWidth = 0.01;
    float line = 1.0 - smoothstep(0.0, lineWidth, minDist);
    
    float3 color = float3(line);
    
    float circleDiameter = 0.03;
    float outerCircleDiameter = 0.045 + 0.015*(cos(time*2) * cos(time*2));
    
    if (length(coordinates - uv) < outerCircleDiameter) {
        color = float3(0.18, 0.44, 0.93) * 0.5;
    }
    if (length(coordinates - uv) < circleDiameter) {
        color = float3(0.18, 0.44, 0.93);
    }
    
    return half4(half3(color), 1.0);
}

[[ stitchable ]] half4 runPathWarpShader(
                                     float2 position,
                                     half4 currentColor,
                                     float time,
                                     float2 size,
                                     float scale,
                                     float2 offset,
                                     float2 coordinates,
                                     float2 direction,
                                     float elevation,
                                     float heartRate,
                                     device const void* pathBuffer,
                                     int pathBytes,
                                     float speed
                                     )
{
    device const float2* path = (device const float2*)pathBuffer;
    int pathCount = pathBytes / sizeof(float2);
    float2 uv = float2(position.x - size.x * 0.5, size.y * 0.5 - position.y) / (size.y * 0.5) * scale + offset;
    
    WarpResult w = runWarp(uv, 5, 0.94, time, direction);
    float2 q = w.q;
    float2 r = w.r;
    float warpStrength = 0.17;
    
    uv += q * warpStrength;
    
    float minDist = 1e9;
    for (int i = 1; i < pathCount; i++) {
        float2 a = path[i - 1];
        float2 b = path[i];
        // project uv onto segment a→b, clamped to [0,1]
        float2 ab = b - a;
        float t = clamp(dot(uv - a, ab) / dot(ab, ab), 0.0, 1.0);
        float2 closest = a + t * ab;
        minDist = min(minDist, length(uv - closest));
    }
    
    float cd = length(coordinates - uv);
    
    float lineWidth = 0.01 + (0.005 * length(r));
    lineWidth += 0.12 * (1 - smoothstep(0.0, 0.25, abs(cd)));
    float line = 1.0 - smoothstep(0.0, lineWidth, minDist);
    
    float3 color = float3(line);
    
    float circleDiameter = 0.03;
    float outerCircleDiameter = 0.045 + 0.015*(cos(time*2) * cos(time*2));
    
    float cd1 = length(coordinates - (uv + sin(time - r) * circleDiameter));
    float cd2 = length(coordinates - (uv + sin(time + M_PI_F + r) * circleDiameter));
    
    circleDiameter += 0.01 * length(r);
    outerCircleDiameter += 0.01 * length(r);
    
    if (cd1 < outerCircleDiameter) {
        color = float3(0.18, 0.44, 0.93) * 0.5;
    }
    if (cd1 < circleDiameter) {
        color = float3(0.18, 0.44, 0.93);
    }
    
    if (cd2 < outerCircleDiameter) {
        color = float3(1.0, 0.22, 0.23) * 0.5;
    }
    if (cd2 < circleDiameter) {
        color = float3(1.0, 0.22, 0.23);
    }
    
    return half4(half3(color), 1.0);
}

[[ stitchable ]] half4 runGradientShader(
                                      float2 position,
                                      half4 currentColor,
                                      float time,
                                      float2 size,
                                      float2 coordinates,
                                      float2 direction,
                                      float elevation,
                                      float heartRate,
                                      float speed
                                      )
{
    return half4(speed, elevation, heartRate, 1);
}
