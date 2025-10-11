#version 330 core
in vec2 fragCoord;
out vec4 FragColor;

// Map uniforms
uniform vec2 uResolution;
uniform float uTime;

// Room mask texture (white = room, black = wall)
uniform sampler2D uRoomMask;
uniform bool uUseTexture;

// Simple SDF for basic shapes (fallback)
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void main() {
    vec2 uv = fragCoord * uResolution;
    
    // Background
    vec3 color = vec3(0.05, 0.05, 0.1);
    
    // Draw grid
    vec2 grid = abs(fract(uv * 0.1) - 0.5);
    float gridLine = smoothstep(0.0, 0.02, min(grid.x, grid.y));
    color = mix(color, vec3(0.1), 1.0 - gridLine);
    
    // Sample room mask texture
    vec2 texCoord = uv / uResolution;
    vec4 roomMask = texture(uRoomMask, texCoord);
    float roomValue = roomMask.r; // Use red channel as room mask
    
    // Draw rooms based on texture or fallback
    if (uUseTexture) {
        // Use texture-based room detection
        if (roomValue > 0.5) {
            // Room area - apply RE2 style
            vec3 roomColor = vec3(0.2, 0.4, 0.6);
            color = roomColor;
        }
    } else {
        // Fallback: simple test rectangle
        vec2 roomPos = vec2(400, 300);
        vec2 roomSize = vec2(100, 80);
        float roomDist = sdBox(uv - roomPos, roomSize * 0.5);
        
        if (roomDist < 0.0) {
            vec3 roomColor = vec3(0.2, 0.4, 0.6);
            color = roomColor;
        }
    }
    
    // Draw walls with drop shadow
    float wallThickness = 2.0;
    float shadowDistance = 5.0;
    
    if (uUseTexture) {
        // Texture-based wall detection
        float wallValue = 1.0 - roomValue; // Invert room mask for walls
        if (wallValue > 0.5) {
            // Wall area
            color = vec3(0.4, 0.4, 0.4);
        }
    } else {
        // Fallback wall rendering
        vec2 roomPos = vec2(400, 300);
        vec2 roomSize = vec2(100, 80);
        float roomDist = sdBox(uv - roomPos, roomSize * 0.5);
        
        float wallDist = abs(roomDist) - wallThickness;
        if (wallDist < 0.0 && roomDist > -wallThickness) {
            color = vec3(0.4, 0.4, 0.4);
        }
    }
    
    FragColor = vec4(color, 1.0);
}