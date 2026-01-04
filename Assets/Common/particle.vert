#version 330 core

// Quad vertex position (location 0)
layout(location = 0) in vec3 aQuadPos;

// Instance attributes
layout(location = 1) in vec3 aInstancePos;  // Particle world position
layout(location = 2) in float aInstanceSize;  // Particle size
layout(location = 3) in vec4 aInstanceColor;  // Particle color
layout(location = 4) in float aInstanceRotation;  // Particle rotation

out vec4 vColor;
out vec2 vUV;

uniform mat4 projection;
uniform mat4 view;
uniform vec3 cameraPosition;

void main() {
  // Billboard transformation: make quad always face camera
  vec3 worldPos = aInstancePos;
  
  // Calculate direction from particle to camera
  vec3 toCamera = normalize(cameraPosition - worldPos);
  
  // Use world up vector to build billboard frame
  vec3 worldUp = vec3(0.0, 1.0, 0.0);
  
  // Calculate right vector (perpendicular to camera direction and world up)
  vec3 right = normalize(cross(worldUp, toCamera));
  
  // Calculate up vector (perpendicular to right and camera direction)
  vec3 up = normalize(cross(toCamera, right));
  
  // Apply rotation to the billboard
  float cosRot = cos(aInstanceRotation);
  float sinRot = sin(aInstanceRotation);
  vec3 rotatedRight = right * cosRot + up * sinRot;
  vec3 rotatedUp = -right * sinRot + up * cosRot;
  
  // Transform quad vertex by size and billboard orientation
  vec3 vertexWorldPos = worldPos + rotatedRight * aQuadPos.x * aInstanceSize + rotatedUp * aQuadPos.y * aInstanceSize;
  
  // Transform to clip space
  gl_Position = projection * view * vec4(vertexWorldPos, 1.0);
  
  // Pass through color and UV
  vColor = aInstanceColor;
  
  // Generate UV coordinates from quad position (-0.5 to 0.5 -> 0.0 to 1.0)
  vUV = aQuadPos.xy + vec2(0.5);
}

