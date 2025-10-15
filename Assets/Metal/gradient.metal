#include <metal_stdlib>
using namespace metal;

struct GradientVertex {
    float2 position [[attribute(0)]];
    float2 gradientCoord [[attribute(1)]];
};

struct GradientVertexOut {
    float4 position [[position]];
    float2 gradientCoord;
};

struct GradientUniforms {
    float4x4 mvp;
    int gradientType; // 0 = linear, 1 = radial
    float2 gradientStart; // For linear: start point, for radial: center point
    float2 gradientEnd; // For linear: end point, for radial: radius vector
    int numColorStops;
    float4 colorStops[16]; // RGBA values
    float colorLocations[16]; // Location values (0.0 to 1.0)
};

vertex GradientVertexOut gradientVertex(GradientVertex in [[stage_in]],
                                      constant GradientUniforms& uniforms [[buffer(0)]]) {
    GradientVertexOut out;
    out.position = uniforms.mvp * float4(in.position, 0.0, 1.0);
    out.gradientCoord = in.gradientCoord;
    return out;
}

fragment float4 gradientFragment(GradientVertexOut in [[stage_in]],
                               constant GradientUniforms& uniforms [[buffer(0)]]) {
    float2 uv = in.gradientCoord;
    
    if (uniforms.gradientType == 0) {
        // Linear gradient
        float2 gradientDir = uniforms.gradientEnd - uniforms.gradientStart;
        float gradientLength = length(gradientDir);
        
        if (gradientLength == 0.0) {
            return uniforms.colorStops[0];
        }
        
        float2 normalizedDir = gradientDir / gradientLength;
        float2 toPoint = uv - uniforms.gradientStart;
        float t = dot(toPoint, normalizedDir) / gradientLength;
        
        // Clamp t to [0, 1]
        t = clamp(t, 0.0, 1.0);
        
        // Find the two color stops that bracket t
        for (int i = 0; i < uniforms.numColorStops - 1; i++) {
            if (t >= uniforms.colorLocations[i] && t <= uniforms.colorLocations[i + 1]) {
                float localT = (t - uniforms.colorLocations[i]) / (uniforms.colorLocations[i + 1] - uniforms.colorLocations[i]);
                return mix(uniforms.colorStops[i], uniforms.colorStops[i + 1], localT);
            }
        }
        
        // Handle edge cases
        if (t <= uniforms.colorLocations[0]) {
            return uniforms.colorStops[0];
        } else {
            return uniforms.colorStops[uniforms.numColorStops - 1];
        }
    } else {
        // Radial gradient
        float2 center = uniforms.gradientStart;
        float2 radiusVec = uniforms.gradientEnd;
        float maxRadius = length(radiusVec);
        
        if (maxRadius == 0.0) {
            return uniforms.colorStops[0];
        }
        
        float distance = length(uv - center);
        float t = distance / maxRadius;
        
        // Clamp t to [0, 1]
        t = clamp(t, 0.0, 1.0);
        
        // Find the two color stops that bracket t
        for (int i = 0; i < uniforms.numColorStops - 1; i++) {
            if (t >= uniforms.colorLocations[i] && t <= uniforms.colorLocations[i + 1]) {
                float localT = (t - uniforms.colorLocations[i]) / (uniforms.colorLocations[i + 1] - uniforms.colorLocations[i]);
                return mix(uniforms.colorStops[i], uniforms.colorStops[i + 1], localT);
            }
        }
        
        // Handle edge cases
        if (t <= uniforms.colorLocations[0]) {
            return uniforms.colorStops[0];
        } else {
            return uniforms.colorStops[uniforms.numColorStops - 1];
        }
    }
}

