#include <metal_stdlib>
using namespace metal;

struct PathVertex {
    float2 position [[attribute(0)]];
};

struct PathVertexOut {
    float4 position [[position]];
};

struct PathUniforms {
    float4x4 mvp;
    float4 color;
};

vertex PathVertexOut pathVertex(PathVertex in [[stage_in]],
                               constant PathUniforms& uniforms [[buffer(0)]]) {
    PathVertexOut out;
    out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
    return out;
}

fragment float4 pathFragment(PathVertexOut in [[stage_in]],
                            constant PathUniforms& uniforms [[buffer(0)]]) {
    return uniforms.color;
}
