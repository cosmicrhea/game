#version 330 core

in vec2 vUV;
in vec4 vColor;
out vec4 fragColor;

uniform sampler2D uAtlas;
uniform vec4 uColor; // fallback color for non-attributed text
uniform vec4 uOutlineColor; // rgba
uniform float uOutlineThickness;

void main() {
  float a = texture(uAtlas, vUV).a;
  // Use per-vertex color if available, otherwise fall back to uniform color
  vec4 finalColor = vColor.a > 0.0 ? vColor : uColor;
  fragColor = vec4(finalColor.rgb, finalColor.a * a);
}
