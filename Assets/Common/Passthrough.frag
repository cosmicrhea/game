#version 410 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D uTexture;

void main() {
  // For shadow map visualization, sample depth and display as grayscale
  float depth = texture(uTexture, TexCoord).r;
  FragColor = vec4(vec3(depth), 1.0);
}

