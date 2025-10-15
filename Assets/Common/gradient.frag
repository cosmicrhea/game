#version 330 core
in vec2 gradientUV;
out vec4 FragColor;

// Gradient uniforms
uniform int gradientType; // 0 = linear, 1 = radial
uniform vec2 gradientStart; // For linear: start point, for radial: center point
uniform vec2 gradientEnd; // For linear: end point, for radial: radius vector
uniform int numColorStops;
uniform vec4 colorStops[16]; // RGBA values
uniform float colorLocations[16]; // Location values (0.0 to 1.0)

// Linear gradient function
vec4 getLinearGradientColor(vec2 uv) {
    // For linear gradients, we use the UV coordinates directly
    // The gradient goes from gradientStart (0,0) to gradientEnd (1,1) in UV space
    vec2 gradientDir = gradientEnd - gradientStart;
    float gradientLength = length(gradientDir);
    
    if (gradientLength == 0.0) {
        return colorStops[0];
    }
    
    vec2 normalizedDir = gradientDir / gradientLength;
    vec2 toPoint = uv - gradientStart;
    float t = dot(toPoint, normalizedDir) / gradientLength;
    
    // Clamp t to [0, 1]
    t = clamp(t, 0.0, 1.0);
    
    // Find the two color stops that bracket t
    for (int i = 0; i < numColorStops - 1; i++) {
        if (t >= colorLocations[i] && t <= colorLocations[i + 1]) {
            float localT = (t - colorLocations[i]) / (colorLocations[i + 1] - colorLocations[i]);
            return mix(colorStops[i], colorStops[i + 1], localT);
        }
    }
    
    // Handle edge cases
    if (t <= colorLocations[0]) {
        return colorStops[0];
    } else {
        return colorStops[numColorStops - 1];
    }
}

// Radial gradient function
vec4 getRadialGradientColor(vec2 uv) {
    vec2 center = gradientStart;
    float maxRadius = gradientEnd.x; // gradientEnd.x stores the radius
    
    if (maxRadius == 0.0) {
        return colorStops[0];
    }
    
    float distance = length(uv - center);
    float t = distance / maxRadius;
    
    // Clamp t to [0, 1]
    t = clamp(t, 0.0, 1.0);
    
    // Simple fallback for debugging - just use the first two colors
    if (numColorStops >= 2) {
        return mix(colorStops[0], colorStops[1], t);
    }
    
    // Find the two color stops that bracket t
    for (int i = 0; i < numColorStops - 1; i++) {
        if (t >= colorLocations[i] && t <= colorLocations[i + 1]) {
            float localT = (t - colorLocations[i]) / (colorLocations[i + 1] - colorLocations[i]);
            return mix(colorStops[i], colorStops[i + 1], localT);
        }
    }
    
    // Handle edge cases
    if (t <= colorLocations[0]) {
        return colorStops[0];
    } else {
        return colorStops[numColorStops - 1];
    }
}

void main() {
    if (gradientType == 0) {
        // Linear gradient
        FragColor = getLinearGradientColor(gradientUV);
    } else {
        // Radial gradient
        FragColor = getRadialGradientColor(gradientUV);
    }
}
