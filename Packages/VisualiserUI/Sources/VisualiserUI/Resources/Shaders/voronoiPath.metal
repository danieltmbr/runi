#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
#include "voronoi.h"

using namespace metal;

// Returns the point of the run path closest to `uv`.
//
// Path points are y-up like the run coordinates while `uv` is y-down, so each
// point is flipped before measuring. Returns a far away point when the path has
// no segment, which disables the path's density increase.
float2 closestPathPoint(
                        device const void* pathBuffer,
                        int pathBytes,
                        float2 uv
                        ) {
    device const float2* path = (device const float2*)pathBuffer;
    int pathCount = pathBytes / sizeof(float2);

    float  nearestD2 = FLT_MAX;
    float2 nearest   = float2(FLT_MAX);
    for (int i = 1; i < pathCount; i++) {
        float2 a = float2(path[i - 1].x, -path[i - 1].y);
        float2 b = float2(path[i].x, -path[i].y);
        float2 ab = b - a;
        float  t = clamp(dot(uv - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
        float2 closest = a + t * ab;
        float2 d = uv - closest;
        float  dd = dot(d, d);
        if (dd < nearestD2) {
            nearestD2 = dd;
            nearest   = closest;
        }
    }

    return nearest;
}

// How strongly `target` asks the cell at `position` to subdivide: 1 on top
// of the target, fading to 0 at `radius`.
float influence(float2 position, float2 target, float radius) {
    float2 h = position - target;
    return 1.0 - smoothstep(0.0, radius * radius, dot(h, h));
}

// Subdivides `cell` when the path or the runner is close enough.
//
// The two influences are combined as a union: the path refines cells up to
// `pathLevels`, the runner — who is on the path — continues up to `runnerLevels`,
// so the path is denser than the field and the runner's surroundings denser still.
void pushPathChildren(
                      Cell cell,
                      float2 pathPoint,
                      float2 runner,
                      float maxRadius,
                      float minRadius,
                      int pathLevels,
                      int runnerLevels,
                      thread Cell *stack,
                      thread int &stackSize
                      ) {
    float r = mix(maxRadius, minRadius, float(cell.level) / float(runnerLevels));
    float tPath   = cell.level < pathLevels   ? influence(cell.position, pathPoint, r) : 0.0;
    float tRunner = cell.level < runnerLevels ? influence(cell.position, runner, r)    : 0.0;
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
float2 voronoiFeature(
                      float2 uv,          // aspect-preserving space, y down, ±1 on the short side
                      float2 pathPosition,
                      float2 runnerPosition,
                      float  gridSize,
                      float  maxRadius,   // density radius at the coarsest level, in uv units
                      float  minRadius    // density radius at the deepest level, in uv units
                      ) {
    float2 runner = runnerPosition * gridSize;
    float2 path   = pathPosition   * gridSize;

    float2 p = uv * gridSize;

    float2 cell  = floor(p);

    // Radii arrive in uv units (1 = half the short side); the search runs in cell units.
    maxRadius *= gridSize;
    minRadius *= gridSize;

    // float t = sin(time)*sin(time);

    const int PATH_LEVELS   = 1;
    const int RUNNER_LEVELS = 3;
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
                pushPathChildren(cell, path, runner, maxRadius, minRadius, PATH_LEVELS, RUNNER_LEVELS, stack, stackSize);
            }
        }

    return nearest.position / gridSize;
}

[[ stitchable ]] half4 pathVoronoi(
                                   float2 position,
                                   SwiftUI::Layer layer,
                                   float2 size,
                                   float gridSize,
                                   float maxRadius,   // density radius at the coarsest level, in uv units
                                   float minRadius,   // density radius at the deepest level, in uv units
                                   float2 coordinates, // current run position in normalised space (-1, 1), y up
                                   device const void* pathBuffer,
                                   int pathBytes
                                   ) {
    float minSide = min(size.x, size.y);
    float2 uv = (2.0 * position - size) / minSide;

    // Run coordinates are y-up while uv is y-down, so flip the vertical axis.
    float2 runner  = float2(coordinates.x, -coordinates.y);
    float2 pathPos = closestPathPoint(pathBuffer, pathBytes, uv);

    float2 sampleUV = voronoiFeature(uv, pathPos, runner, gridSize, maxRadius, minRadius);
    float2 samplePosition = (sampleUV * minSide + size) * 0.5;

    // Edge cells can have their feature point off-screen; clamp so they sample
    // the nearest edge pixel instead of reading outside the layer bounds.
    samplePosition = clamp(samplePosition, float2(0.5), size - float2(0.5));
    return layer.sample(samplePosition);
}
