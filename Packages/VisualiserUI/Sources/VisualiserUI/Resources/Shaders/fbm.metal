#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

float3 noised(float2 position);

float fbm(float2 position, float octaves, float h)
{
    const float2x2 m = float2x2(0.80, 0.60, -0.60, 0.80);
    float g = exp2(-h);
    float f = 1.0;
    float a = 1.0;
    float t = 0.0;
    for(int i=0; i<12; i++ )
    {
        t += a * noised(f * position).x * clamp(octaves - float(i), 0.0, 1.0);
        position = m * position;
        f *= 2.01 + i * 0.01;
        a *= g;
    }
    return t;
}

float3 fbmd(float2 position, float octaves, float h) {
    float g = exp2(-h);
    float f = 1.0;
    float a = 1.0;
    float t = 0.0;
    // accumulate derivatives
    float2 d = float2(0.0);
        
    for(int i = 0; i < octaves; i++) {
        float3 n = noised(f * position);
        t += a * n.x;
        // accumulate derivatives (note: multiply by f for chain rule)
        d += a * n.yz * f;
        
        f *= 2.01 + i * 0.01;
        a *= g;
    }
    return float3(t, d);
}

[[ stitchable ]] half4 fbmShader(
                                 float2 position,
                                 half4 color,
                                 float time,
                                 float octaves,
                                 float h,
                                 float scale
                                 ) {
    // Normalize position to a reasonable scale
    float2 uv = position * scale;
    
    // Get fBM value
    float value = fbm(uv, octaves, h);
    
    // Map from [-1, 1] range to [0, 1] for display
    value = value * 0.5 + 0.5;
    
    // Clamp to valid color range
    value = clamp(value, 0.0, 1.0);
    
    // Return grayscale color
    return half4(half3(value), 1.0);

}
