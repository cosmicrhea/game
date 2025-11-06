#version 330 core
out vec4 FragColor;

in vec2 vUV;

uniform sampler2D albedo_texture;
uniform sampler2D mist_texture;
uniform float near;
uniform float far;
uniform mat4 view_to_clip_matrix;

// Debug mode: true = show mist only, false = show normal albedo
uniform bool showMist;

void main() {
    // Flip UV Y coordinate to match Godot (UV *= vec2(1, -1) in vertex shader)
    vec2 flippedUV = vec2(vUV.x, 1.0 - vUV.y);

    // Sample mist texture (negated like Godot: -texture(mist_texture, UV).x)
    float depth = -texture(mist_texture, flippedUV).r;

    // Reconstruct view-space Z from mist value
    float viewZ = depth * (far - near) - near;

    // Transform view-space position to clip space using projection matrix
    vec4 clip_space = view_to_clip_matrix * vec4(0.0, 0.0, viewZ, 1.0);
    clip_space.z /= clip_space.w;

    // Map NDC [-1,1] to window depth [0,1]
    gl_FragDepth = 0.5 * (clip_space.z + 1.0);

    // Sample textures
    vec3 albedo = texture(albedo_texture, flippedUV).rgb;
    vec3 mist = texture(mist_texture, flippedUV).rgb;

    // Debug visualization: show mist or normal albedo
    if (showMist) {
        // Show mist only
        FragColor = vec4(mist, 1.0);
    } else {
        // Normal mode - just albedo
        FragColor = vec4(albedo, 1.0);
    }
}

//
// Original Godot shader:
//
// void fragment() {
//   float depth = -texture(mist_texture, UV).x;
//   vec4 clip_space = PROJECTION_MATRIX * vec4(0, 0, depth * (far - near) - near, 1);
//   clip_space.z /= clip_space.w;
//     // clip_space.z = 0.5 * (clip_space.z + 1.0); // needed for compatibility renderer
//
//   ALBEDO = texture(albedo_texture, UV).rgb;
//   DEPTH = clip_space.z;
// }
//
