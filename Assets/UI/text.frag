#version 330 core

in vec2 vUV;
in vec4 vColor;
out vec4 fragColor;

uniform sampler2D uAtlas;
uniform vec4 uColor; // fallback color for non-attributed text

void main() {
  float a = texture(uAtlas, vUV).a;
  // Always use uniform color for outline/shadow effects, per-vertex color for main text
  vec4 finalColor = uColor;
  fragColor = vec4(finalColor.rgb, finalColor.a * a);
}
