#version 330 core
out vec4 FragColor;

in vec3 Normal;
in vec3 FragPos;

// Shadow map uniforms
uniform vec3 lightDirection;
uniform sampler2D shadowMap;
uniform bool hasShadowMap;
uniform mat4 lightSpaceMatrix;
uniform float shadowIntensity;
uniform bool shadowCatcherDebugColor;

// Shadow calculation function (manual PCF)
float calculateShadow(vec3 fragPos, vec3 normal, vec3 lightDir) {
  if (!hasShadowMap) return 0.0;
  
  // Transform fragment position to light space
  vec4 fragPosLightSpace = lightSpaceMatrix * vec4(fragPos, 1.0);
  
  // Perspective divide
  vec3 projCoords = fragPosLightSpace.xyz / fragPosLightSpace.w;
  
  // Transform to [0,1] range
  projCoords = projCoords * 0.5 + 0.5;
  
  // Check if fragment is outside shadow map
  if (projCoords.x < 0.0 || projCoords.x > 1.0 ||
      projCoords.y < 0.0 || projCoords.y > 1.0 ||
      projCoords.z > 1.0 || projCoords.z < 0.0) {
    return 0.0; // Outside shadow map, assume lit
  }
  
  float closestDepth = texture(shadowMap, projCoords.xy).r;
  float currentDepth = projCoords.z;
  
  // If shadow map is all white (1.0 = far plane), return no shadow
  if (closestDepth >= 0.999 || currentDepth >= 0.999) {
    return 0.0;
  }
  
  // Add bias to prevent shadow acne
  float bias = max(0.05 * (1.0 - dot(normal, lightDir)), 0.005);
  
  float shadow = 0.0;
  vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
  for (int x = -1; x <= 1; ++x) {
    for (int y = -1; y <= 1; ++y) {
      vec2 offset = vec2(x, y) * texelSize;
      float pcfDepth = texture(shadowMap, projCoords.xy + offset).r;
      shadow += (currentDepth - bias > pcfDepth) ? 1.0 : 0.0;
    }
  }
  shadow /= 9.0;
  
  return shadow;
}

void main() {
  // DEBUG: Render as solid color (cyan) to see geometry
  if (shadowCatcherDebugColor) {
    FragColor = vec4(0.0, 1.0, 1.0, 1.0);
    return;
  }
  
  if (!hasShadowMap) {
    // No shadow map: output hot magenta to make failure obvious
    FragColor = vec4(1.0, 0.0, 1.0, 1.0);
    return;
  }
  
  vec3 L1 = normalize(-lightDirection);
  vec3 N = normalize(Normal);
  float shadowAmount = calculateShadow(FragPos, N, L1);
  
  float shadowFactor = 1.0 - (shadowAmount * shadowIntensity);
  
  FragColor = vec4(shadowFactor, shadowFactor, shadowFactor, 1.0);
}
