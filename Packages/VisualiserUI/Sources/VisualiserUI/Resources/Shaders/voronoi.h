#ifndef Header_h
#define Header_h

#pragma once
#include <metal_stdlib>
using namespace metal;

struct Cell {
    float2 origin;
    float2 position;
    float2 target;
    int    level;
};

float2 hash2( float2 p );

float levelMultiplier(int level);
float4x2 childrenOffsets(int level);
float4x2 childrenCells(int level, float2 parent);
float4x2 childrenCells(float2 parent, float4x2 offsets);
float4x2 features(int level, float4x2 children);
float4x2 childrenFeatures(int level, float2 parent);
float2 dynamicDensityVoronoiFeature(
    float2 uv,         // aspect-preserving space, y down, ±1 on the short side
    float gridSize,
    float maxRadius,   // density radius at the coarsest level, in uv units
    float minRadius,   // density radius at the deepest level, in uv units
    float2 focus       // centre of the density increase, in uv space
);

#endif /* Header_h */
