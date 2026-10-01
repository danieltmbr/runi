#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
#include "voronoi.h"
using namespace metal;

float2 hash2( float2 p )
{
    //p = mod(p, 4.0); // tile
    p = float2(dot(p, float2(127.1,311.7)),
               dot(p, float2(269.5,183.3)));
    return fract(sin(p) * 43758.5453);
}

float2 warpCoordinate(float2 p, float2 c, float a, float w) {
    float  r = length(p - c);
    float2 s = 1.0 + a * exp(-r*r / (w * w));
    return c + s * (p - c);
}

float2 inverseWarpCoordinate(float2 u, float2 c, float a, float w) {
    float2 dir = u - c;
    float  rho = length(dir); // = s * r; r = |p - c|;
    
    if (rho < 0.000001) return c;

    float rMin = rho / (1.0 + a);
    float rMax = rho;
    float r = 0.5 * (rMin + rMax);
    float e  = FLT_MAX;
        
    for (int i = 0; i < 6; i++) {
        float s = 1.0 + a * exp(-r*r / (w * w));
        float f  = s * r;
        e = f - rho;
        
        if (abs(e) < 0.001)
            break;
        
        float df = 1.0 + a * exp(-r*r / (w * w)) * (1.0 - (2*r*r/(w*w)));

        if (abs(df) < 0.0001)
            break;
        
        r = r - (e / df);
    }
    
    return c + normalize(dir) *r;
}

[[ stitchable ]] half4 voronoi(
                               float2 position,
                               SwiftUI::Layer layer,
                               float2 size,
                               float gridSize,
                               float a,
                               float w
                               ) {
    float minSide = min(size.x, size.y);
    float2 uv = (2.0 * position - size) / minSide;
    
    float2 warpedUV = warpCoordinate(uv, float2(0.5, -0.5), a, w);
    float2 p = warpedUV * gridSize;
    float2 n = floor(p);
    float2 f = fract(p);
    
    float  distance       = 8.0;
    float2 nearestFeature = float2(0);
    float2 nearestOffset  = float2(0);
    
    for (int i = -1; i <= 1; i++)
    for (int j = -1; j <= 1; j++) {
        
        float2 b = float2(i, j);
        float2 r = b + hash2(n + b) - f;
        float  d = dot(r, r);
        
        if (d < distance) {
            nearestFeature = r;
            nearestOffset  = b;
            distance       = d;
        }
    }
    
    distance = 8.0;
    for (int i = -2; i <= 2; i++)
    for (int j = -2; j <= 2; j++) {
        
        float2 b = nearestOffset + float2(i, j);
        float2 r = b + hash2(n + b) - f;
        
        float2 delta = r - nearestFeature;
        if (dot(delta, delta) < 0.00001)
            continue;
        
        float  d = dot(0.5*(nearestFeature + r), normalize(r-nearestFeature));
        distance = min(distance, d);
    }
            
    float2 warpedSampleUV = warpedUV + nearestFeature / gridSize;
    float2 sampleUV = inverseWarpCoordinate(warpedSampleUV, float2(0.5, -0.5), a, w);
    float2 samplePosition = (sampleUV * minSide + size) * 0.5;
    half4  color = layer.sample(samplePosition);
    
    color.xzy = mix(half3(1, 1, 1), color.xzy, smoothstep(0, 0.05, distance));
    return color;
}

// MARK: - Dynamic Density Voronoi

float levelMultiplier(int level) {
    float m = 1;
    for (int i = 0; i < level; i++) {
        m *= 0.5;
    }
    return m;
}

float4x2 childrenOffsets(int level) {
    if (level == 0) return float4x2(0.0);
    
    float m = levelMultiplier(level);
    return float4x2(float2(0, 0), float2(m, 0), float2(0, m), float2(m, m));
}

float4x2 childrenCells(int level, float2 parent) {
    float4x2 offsets = childrenOffsets(level);
    return float4x2(parent, parent, parent, parent) + offsets;
}

float4x2 childrenCells(float2 parent, float4x2 offsets) {
    return float4x2(parent, parent, parent, parent) + offsets;
}

float4x2 features(int level, float4x2 children) {
    if (level == 0) return float4x2(0.0);
    
    float  m = levelMultiplier(level);
    float2 h = level * float2(173.0, 269.0);
    
    float4x2 targets = float4x2();
    for (int k = 0; k < 4; k++) {
        targets[k] = hash2(children[k] / m + h);
    }
    
    return children + m * targets;
}

float4x2 childrenFeatures(int level, float2 parent) {
    if (level == 0) return float4x2(0.0);
    float4x2 offsets  = childrenOffsets(level);
    float4x2 children = childrenCells(parent, offsets);
    return features(level, children);
}

void pushChildren(
                  Cell cell,
                  float2 runner,
                  float maxRadius,
                  float minRadius,
                  int maxLevels,
                  thread Cell *stack,
                  thread int &stackSize
                  ) {
    float r = mix(maxRadius, minRadius, float(cell.level) / float(maxLevels));
    float2 h = cell.position - runner;
    float t = 1.0 - smoothstep(0.0, r * r, dot(h, h));
    
    if ( t <= 0.001 || cell.level >= maxLevels) return;
    
    int level = cell.level + 1;
    float4x2 childCells    = childrenCells(level, cell.origin);
    float4x2 childFeatures = features(level, childCells);
    
    for (int c=0; c<4; c++) {
        stack[stackSize++] = {
            .origin   = childCells[c],
            .position = mix(cell.position, childFeatures[c], t),
            .target   = childFeatures[c],
            .level    = level
        };
    }
}

// Returns the voronoi feature point nearest to `uv`, in uv space.
//
// The grid subdivides hierarchically around `focus`, so cells get smaller —
// and feature points denser — the closer they are to it. Shared by the live
// `dynamicDensityVoronoi` shader and the `export_voronoi_fragment` in export.metal,
// which only differ in how they sample the photo at the returned point.
float2 dynamicDensityVoronoiFeature(
                                    float2 uv,         // aspect-preserving space, y down, ±1 on the short side
                                    float gridSize,
                                    float maxRadius,   // density radius at the coarsest level, in uv units
                                    float minRadius,   // density radius at the deepest level, in uv units
                                    float2 focus       // centre of the density increase, in uv space
                                    ) {
    float2 runner = focus * gridSize;

    float2 p = uv * gridSize;

    float2 cell  = floor(p);
    float2 local = fract(p);

    // Radii arrive in uv units (1 = half the short side); the search runs in cell units.
    maxRadius *= gridSize;
    minRadius *= gridSize;

    // float t = sin(time)*sin(time);

    const int MAX_LEVELS = 4;
    Cell stack[16];
    int stackSize = 0;
    
    float nearestD2 = FLT_MAX;
    Cell  nearest;
    
    for (int i = -1; i <= 1; i++)
    for (int j = -1; j <= 1; j++) {
        
        float2 offset = float2(i, j);
        float2 parentCell = cell + offset;
        float2 feature = parentCell + hash2(parentCell);
        
        stack[stackSize++] = {
            .origin   = parentCell,
            .position = feature,
            .target   = feature,
            .level    = 0
        };
        
        while (stackSize) {
            Cell cell = stack[--stackSize];
            float2 d = cell.position - p;
            float dd = dot(d, d);
            if (nearestD2 > dd) {
                nearestD2  = dd;
                nearest = cell;
            }
            pushChildren(cell, runner, maxRadius, minRadius, MAX_LEVELS, stack, stackSize);
        }
    }
    
    return nearest.position / gridSize;
}

[[ stitchable ]] half4 dynamicDensityVoronoi(
                                             float2 position,
                                             SwiftUI::Layer layer,
                                             float2 size,
                                             float gridSize,
                                             float maxRadius,   // density radius at the coarsest level, in uv units
                                             float minRadius,   // density radius at the deepest level, in uv units
                                             float2 coordinates // current run position in normalised space (-1, 1), y up
                                             ) {
    float minSide = min(size.x, size.y);

    float2 uv = (2.0 * position - size) / minSide;

    // Run coordinates are y-up while uv is y-down, so flip the vertical axis.
    float2 runner = float2(coordinates.x, -coordinates.y);

    float2 sampleUV = dynamicDensityVoronoiFeature(uv, gridSize, maxRadius, minRadius, runner);
    float2 samplePosition = (sampleUV * minSide + size) * 0.5;

    // Edge cells can have their feature point off-screen; clamp so they sample
    // the nearest edge pixel instead of reading outside the layer bounds.
    samplePosition = clamp(samplePosition, float2(0.5), size - float2(0.5));
    return layer.sample(samplePosition);
}
