#version 330 core

layout(location = 0) in vec2 aPos; // pixel space
layout(location = 1) in vec2 aUV;
layout(location = 2) in vec4 aColor; // per-vertex color

out vec2 vUV;
out vec4 vColor;

uniform mat4 uMVP;

void main() {
  vUV = vec2(aUV.x, 1.0 - aUV.y);
  vColor = aColor;
  gl_Position = uMVP * vec4(aPos, 0.0, 1.0);
}
