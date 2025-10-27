#version 330 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aTexCoord;

out vec2 vUV;

uniform float uAspectRatio;

void main() {
  // Apply aspect ratio correction to prevent stretching
  vec2 correctedPos = aPos;
  correctedPos.y /= uAspectRatio; // Try correcting Y instead of X

  gl_Position = vec4(correctedPos, 0.0, 1.0);
  // Pass UVs as-is, we'll flip in fragment shader
  vUV = aTexCoord;
}
