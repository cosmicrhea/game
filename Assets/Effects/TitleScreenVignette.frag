#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D uTexture;
uniform vec2 uResolution;
uniform float amount; // Vignette strength (0.0 = no effect, 1.0 = full effect)

void main() {
    vec2 uv = TexCoord * uResolution;
    
    // Sample the input texture
    vec4 texColor = texture(uTexture, TexCoord);
    
    // Apply vignette effect (same as MapView.frag)
    vec2 center = uResolution * 0.5;
    float distFromCenter = length(uv - center);
    float maxDist = length(uResolution * 0.5);
    float vignette = 1.0 - smoothstep(0.0, maxDist * 0.8, distFromCenter);
    vignette = mix(1.0, vignette, amount);
    
    // Apply vignette to final color
    vec3 color = texColor.rgb * vignette;
    
    FragColor = vec4(color, texColor.a);
}
