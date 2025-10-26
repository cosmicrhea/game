#version 330 core
out vec4 FragColor;

in vec2 vUV;

// Uniforms matching the Godot shader
uniform sampler2D albedo_texture;
uniform sampler2D mist_texture;
uniform sampler2D depth_texture;
uniform float near;
uniform float far;

void main() {
    // Sample depth from mist texture (negative value as in Godot)
    float depth = -texture(mist_texture, vUV).x;
    
    // Calculate clip space position
    // In Godot: PROJECTION_MATRIX * vec4(0, 0, depth * (far - near) - near, 1)
    // For GLSL, we need to simulate the projection matrix transformation
    vec4 clip_space = vec4(0.0, 0.0, depth * (far - near) - near, 1.0);
    
    // Apply perspective projection (assuming standard perspective projection)
    // This is a simplified version - you may need to adjust based on your actual projection matrix
    clip_space.z = (clip_space.z * (far + near) / (far - near)) - (2.0 * far * near / (far - near));
    clip_space.z /= clip_space.w;
    
    // Set depth buffer value
    gl_FragDepth = clip_space.z;
    
    // Sample albedo color
    vec3 albedo = texture(albedo_texture, vUV).rgb;
    
    FragColor = vec4(albedo, 1.0);
}
