#version 330 core
layout (location = 0) in vec2 position;
layout (location = 1) in vec2 gradientCoord;

out vec2 gradientUV;

uniform mat4 mvp;

void main() {
    gl_Position = mvp * vec4(position, 0.0, 1.0);
    gradientUV = gradientCoord;
}



