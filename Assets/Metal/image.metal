#include <metal_stdlib>
using namespace metal;

struct ImageVertex {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct ImageVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct ImageUniforms {
    float4x4 mvp;
    float4 tint;
};

vertex ImageVertexOut imageVertex(ImageVertex in [[stage_in]],
                                 constant ImageUniforms& uniforms [[buffer(0)]]) {
    ImageVertexOut out;
    out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
    out.uv = float2(in.uv.x, 1.0 - in.uv.y);
    return out;
}

fragment float4 imageFragment(ImageVertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]],
                             constant ImageUniforms& uniforms [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 texel = texture.sample(textureSampler, in.uv);
    return texel * uniforms.tint;
}
