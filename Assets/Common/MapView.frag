#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform vec2 uResolution;
uniform float uGridScale;
uniform float uGridOpacity;
uniform float uVignetteStrength;
uniform float uVignetteRadius;

// Grid size control
uniform float uGridCellSize;

// Color uniforms
uniform vec3 uBackgroundColor;
uniform vec3 uGridColor;
uniform float uGridThickness;

void main() {
    vec2 uv = TexCoord * uResolution;
    
    // Use uniform background color
    vec3 color = uBackgroundColor;
    
    // Simple grid - INVERTED to get light lines
    float gridSpacing = uGridCellSize * uGridScale;
    vec2 gridUV = uv / gridSpacing;
    vec2 grid = abs(fract(gridUV) - 0.5);
    
    // Convert pixel thickness to normalized coordinates
    float pixelThickness = uGridThickness / gridSpacing;
    float gridLine = 1.0 - smoothstep(0.0, pixelThickness, min(grid.x, grid.y));
    
    // Add grid lines using uniform color
    color += uGridColor * gridLine * uGridOpacity;
    
    // Apply vignette effect
    vec2 center = uResolution * 0.5;
    float distFromCenter = length(uv - center);
    float maxDist = length(uResolution * 0.5);
    float vignette = 1.0 - smoothstep(0.0, maxDist * uVignetteRadius, distFromCenter);
    vignette = mix(1.0, vignette, uVignetteStrength);
    
    // Apply vignette to final color
    color *= vignette;
    
    FragColor = vec4(color, 1.0);
}
