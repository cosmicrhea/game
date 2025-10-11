#version 410 core

in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D uTexture;
uniform float uOpacity;

void main()
{
    vec4 originalColor = texture(uTexture, TexCoord);
    
    // Create a fade effect by blending with black based on opacity
    vec3 fadeColor = mix(originalColor.rgb, vec3(0.0), uOpacity);
    
    FragColor = vec4(fadeColor, 1.0);
}
