#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec2 aTexCoord;

out vec2 vUV;

void main() {
  gl_Position = vec4(aPos, 1.0);
  // Flip UV vertically to match Godot's coordinate system
  vUV = aTexCoord * vec2(1.0, -1.0);
}
