#version 330 core

in vec2 vUV;
out vec4 fragColor;

uniform sampler2D uTexture;
uniform float uAlpha;

void main() {
  vec4 texel = texture(uTexture, vUV);
  fragColor = vec4(texel.rgb, texel.a * uAlpha);
}
