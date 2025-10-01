#version 330 core

in vec2 vUV;
out vec4 fragColor;

uniform sampler2D uTexture;
uniform vec4 uTint; // rgba multiply

void main() {
  vec4 texel = texture(uTexture, vUV);
  fragColor = texel * uTint;
}


