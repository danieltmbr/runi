#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

struct WarpResult {
    float f;
    float2 q;
    float2 r;
};

float fbm(float2 position, float octaves, float h);

float3 fbmd(float2 position, float octaves, float h);

float3 color(float t, float3 a, float3 b, float3 c, float3 d)
{
    return a + b * cos(6.283185 * (c * t + d));
}

float3 palette1(float t)
{
    float3 a = float3(0.8, 0.5, 0.4);
    float3 b = float3(0.2, 0.4, 0.2);
    float3 c = float3(1.0, 1.0, 1.0);
    float3 d = float3(0.0, 0.15, 0.20);

    return color(t, a, b, c, d);
}

WarpResult warp(float2 p, float octaves, float h, float time)
{
    float2 q = float2(
                      fbm(p + float2(0.7, 2.1), octaves, h),
                      fbm(p + float2(5.2, 1.3), octaves, h)
                      );
    
    float2 r = float2(
                      fbm(p + 4.0 * q + float2(1.7, 9.2), octaves, h),
                      fbm(p + 4.0 * q + float2(8.3, 2.8), octaves, h)
                      );

    float f = fbm(p + 4.0 * r, octaves, h);

    WarpResult result;
    result.f = f;
    result.q = q;
    result.r = r;
    return result;
}

// Domain warp driven by pace-weighted time + running direction.
//
// Same displacement computation as `warp()` but adds directional amplification:
// the component of the first warp layer (q) that already points in the running
// direction is boosted, making distortion stronger in the direction of travel
// while leaving perpendicular flow completely unchanged.
//
WarpResult runWarp(float2 p, float octaves, float h, float animTime, float2 flowDir) {

    // First warp layer — Inigo's opposing time signs for organic, non-repeating swirl.
    float2 q = float2(
        fbm(p + float2(0.7, 2.1) + animTime * 0.04,  octaves, h),
        fbm(p + float2(5.2, 1.3) - animTime * 0.04,  octaves, h)
    );

    // Directional distortion amplification.
    // Project q onto the running direction and boost that component.
    // Where the warp already wants to push in the running direction it pushes harder;
    // perpendicular displacement is completely unchanged.
    float mag = length(flowDir);
    if (mag > 0.05) {
        float2 rDir = flowDir / mag;
        q += rDir * dot(q, rDir) * mag * 0.7;
    }

    // Second warp layer — uses the (possibly boosted) q.
    // 1.26× ratio on the opposing sign breaks symmetry (from lsl3RH).
    float2 r = float2(
        fbm(p + 4.0*q + float2(1.7, 9.2) + animTime * 0.06,   octaves, h),
        fbm(p + 4.0*q + float2(8.3, 2.8) - animTime * 0.0756, octaves, h)
    );

    float f = fbm(p + 4.0*r, octaves, h);

    WarpResult result;
    result.f = f;
    result.q = q;
    result.r = r;
    return result;
}

[[ stitchable ]] half4 warpShader(
                                  float2 position,
                                  half4 color,
                                  float time,
                                  float octaves,
                                  float h,
                                  float scale
                                  )
{
    // Normalize position to a reasonable scale
    float2 uv = position * scale;
    WarpResult w = warp(uv, octaves, h, time);

    float f = clamp(w.f * 0.5 + 0.5, 0.0, 1.0);
    float2 q = w.q;
    float2 r = w.r;

    // Base color from warp amount
    float warpMag = clamp(length(q) * 0.5 + length(r) * 0.3, 0.0, 1.0);
    float3 c = palette1(warpMag);
    
    // Mix in white where second warp is strong (like his dot(n,n))
    float rS = clamp(dot(r, r) * 0.2, 0.0, 1.0);
    c = mix(c, float3(0.9, 0.95, 1.0), rS);
    
    // Add edge highlighting
    float edges = smoothstep(0.8, 1.2, abs(r.x) + abs(r.y));
    c = mix(c, float3(0.1, 0.4, 0.5), edges * 0.3);
    
    // Textrue details
    c *= 0.7 + 0.3 * f;
    
    return half4(half3(c), 1.0);
}
