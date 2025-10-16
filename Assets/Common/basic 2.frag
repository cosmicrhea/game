// #version 330 core
// out vec4 FragColor;

// in vec2 TexCoord;

// uniform sampler2D diffuseTexture;
// uniform bool hasTexture;

// void main() {
//   if (hasTexture) {
//     FragColor = texture(diffuseTexture, TexCoord);
//   } else {
//     // Fallback color when no texture
//     FragColor = vec4(0.8f, 0.15f, 0.6f, 1.0f);
//   }
// }

#version 330 core
out vec4 FragColor;

in vec2 TexCoord;

uniform sampler2D diffuseTexture;
uniform bool hasTexture;

// Lighting uniforms
uniform vec3 lightDirection;
uniform vec3 lightColor;
uniform float lightIntensity;

void main() {
  vec4 baseColor;
  
  if (hasTexture) {
    baseColor = texture(diffuseTexture, TexCoord);
  } else {
    // Fallback color when no texture
    baseColor = vec4(0.8f, 0.15f, 0.6f, 1.0f);
  }
  
  // Simple directional lighting
  // For now, assume all surfaces face up (normal = 0, 1, 0)
  // In a real implementation, you'd pass normals from the vertex shader
  vec3 normal = vec3(0.0, 1.0, 0.0);
  
  // Calculate diffuse lighting
  float NdotL = max(dot(normal, -lightDirection), 0.0);
  vec3 lighting = lightColor * lightIntensity * NdotL;
  
  // Add some ambient light so nothing is completely black
  vec3 ambient = vec3(0.3, 0.3, 0.3);
  
  // Combine lighting with base color
  vec3 finalColor = (ambient + lighting) * baseColor.rgb;
  
  FragColor = vec4(finalColor, baseColor.a);
}
