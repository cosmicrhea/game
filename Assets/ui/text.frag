#version 330 core

in vec2 vUV;
out vec4 fragColor;

uniform sampler2D uAtlas;
uniform vec4 uColor; // rgba

void main() {
  float a = texture(uAtlas, vUV).a;
  fragColor = vec4(uColor.rgb, uColor.a * a);
}
