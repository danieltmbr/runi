#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
#include "voronoi.h"

using namespace metal;

struct Sample {
    Cell cell;
    float2 position;
};

// Distance of `uv` to the run path, in uv units, read from the distance
// field rendered by `PathDistanceFieldRenderer`. The field covers the uv square
// [-extent, extent]² and encodes `min(distance / maxDistance, 1)`.
float pathDistance(
                   texture2d<half, access::sample> field,
                   float extent,
                   float maxDistance,
                   float2 uv
                   ) {
    constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 coord = (uv + extent) / (2.0 * extent);
    return float(field.sample(fieldSampler, coord).r) * maxDistance;
}

// How strongly `target` asks the cell at `position` to subdivide: 1 on top
// of the target, fading to 0 at `radius`.
float influence(float2 position, float2 target, float radius) {
    float2 h = position - target;
    return 1.0 - smoothstep(0.0, radius * radius, dot(h, h));
}

// Subdivides `cell` when the path or the runner is close enough.
//
// Both influences depend on the cell only — never on the pixel being shaded —
// so every pixel of a cell agrees on where the cell's feature point is.
// They are combined as a union: the path refines cells up to `pathLevels`
// within a band of constant `pathRadius`; the runner — who is on the path —
// continues up to `runnerLevels` within a radius tapering from `maxRadius`
// to `minRadius`, so the path is denser than the field and the runner's
// surroundings denser still.
void pushPathChildren(
                      Cell cell,
                      texture2d<half, access::sample> pathField,
                      float fieldExtent,
                      float fieldMaxDistance,
                      float2 runner,
                      float gridSize,
                      float maxRadius,
                      float minRadius,
                      float pathRadius,
                      int pathLevels,
                      int runnerLevels,
                      thread Cell *stack,
                      thread int &stackSize
                      ) {
    float r = mix(maxRadius, minRadius, float(cell.level) / float(runnerLevels));

    // The field is in uv units while the search runs in cell units.
    float d = pathDistance(pathField, fieldExtent, fieldMaxDistance, cell.position / gridSize) * gridSize;
    float tPath   = cell.level < pathLevels   ? 1.0 - smoothstep(0.0, pathRadius * pathRadius, d * d) : 0.0;
    float tRunner = cell.level < runnerLevels ? influence(cell.position, runner, r) : 0.0;
    float t = max(tPath, tRunner);

    if (t <= 0.001) return;

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
// The grid subdivides hierarchically along the run path and, deeper still,
// around the runner, so cells get smaller — and feature points denser — the
// closer they are to either.
Sample voronoiFeature(
                      float2 uv,          // aspect-preserving space, y down, ±1 on the short side
                      texture2d<half, access::sample> pathField,
                      float  fieldExtent,
                      float  fieldMaxDistance,
                      float2 runnerPosition,
                      float  gridSize,
                      float  maxRadius,   // runner density radius at the coarsest level, in uv units
                      float  minRadius,   // runner density radius at the deepest level, in uv units
                      float  pathRadius   // half width of the path band, in uv units
                      ) {
    float2 runner = runnerPosition * gridSize;
    
    float2 p = uv * gridSize;
    float2 cell  = floor(p);
    
    // Radii arrive in uv units (1 = half the short side); the search runs in cell units.
    maxRadius  *= gridSize;
    minRadius  *= gridSize;
    pathRadius *= gridSize;
    
    // float t = sin(time)*sin(time);
    
    const int PATH_LEVELS   = 2;
    const int RUNNER_LEVELS = 4;
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
                pushPathChildren(cell, pathField, fieldExtent, fieldMaxDistance, runner, gridSize,
                                 maxRadius, minRadius, pathRadius, PATH_LEVELS, RUNNER_LEVELS, stack, stackSize);
            }
        }
    
    return {
        .cell = nearest,
        .position = nearest.position / gridSize
    };
}

[[ stitchable ]] half4 pathVoronoi(
                                   float2 position,
                                   SwiftUI::Layer layer,
                                   float2 size,
                                   float gridSize,
                                   float maxRadius,   // runner density radius at the coarsest level, in uv units
                                   float minRadius,   // runner density radius at the deepest level, in uv units
                                   float pathRadius,  // half width of the path band, in uv units
                                   float2 coordinates, // current run position in normalised space (-1, 1), y up
                                   float fieldExtent,      // half side of the uv square the path field covers
                                   float fieldMaxDistance, // path distance encoded as 1.0 in the field
                                   texture2d<half, access::sample> pathField [[texture(0)]]
                                   ) {
    float minSide = min(size.x, size.y);
    float2 uv = (2.0 * position - size) / minSide;

    // Run coordinates are y-up while uv is y-down, so flip the vertical axis.
    float2 runner = float2(coordinates.x, -coordinates.y);

    Sample sample = voronoiFeature(
                                   uv,
                                   pathField,
                                   fieldExtent,
                                   fieldMaxDistance,
                                   runner,
                                   gridSize,
                                   maxRadius,
                                   minRadius,
                                   pathRadius
                                   );
    
    float2 samplePosition;
    if (sample.cell.level > 3) {
        samplePosition = position; //(sample.position * minSide + size) * 0.5;
    } else {
        samplePosition = (sample.position * minSide + size) * 0.5;
        // Edge cells can have their feature point off-screen; clamp so they sample
        // the nearest edge pixel instead of reading outside the layer bounds.
        samplePosition = clamp(samplePosition, float2(0.5), size - float2(0.5));
    }

    return layer.sample(samplePosition);
}
