#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec3 Normal;
in vec3 FragPos;
in vec3 Tangent;
in vec3 Bitangent;

// PBR Texture uniforms
uniform sampler2D diffuseTexture;
uniform sampler2D normalTexture;
uniform sampler2D roughnessTexture;
uniform sampler2D metallicTexture;
uniform sampler2D aoTexture;

// HDRI Environment map
uniform samplerCube environmentMap;
uniform bool hasEnvironmentMap;

// Debug controls
uniform bool diffuseOnly;

uniform bool hasDiffuseTexture;
uniform bool hasNormalTexture;
uniform bool hasRoughnessTexture;
uniform bool hasMetallicTexture;
uniform bool hasAoTexture;

// Material properties
uniform vec3 baseColor;
uniform float metallic;
uniform float roughness;
uniform vec3 emissive;
uniform float opacity;

// Lighting uniforms
uniform vec3 lightDirection;
uniform vec3 lightColor;
uniform float lightIntensity;
uniform vec3 fillLightDirection;
uniform vec3 fillLightColor;
uniform float fillLightIntensity;
uniform vec3 cameraPosition;

// PBR functions
vec3 fresnelSchlick(float cosTheta, vec3 F0) {
  return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

float DistributionGGX(vec3 N, vec3 H, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float NdotH = max(dot(N, H), 0.0);
  float NdotH2 = NdotH * NdotH;
  
  float num = a2;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  denom = 3.14159265359 * denom * denom;
  
  return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
  float r = (roughness + 1.0);
  float k = (r * r) / 8.0;
  
  float num = NdotV;
  float denom = NdotV * (1.0 - k) + k;
  
  return num / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
  float NdotV = max(dot(N, V), 0.0);
  float NdotL = max(dot(N, L), 0.0);
  float ggx2 = GeometrySchlickGGX(NdotV, roughness);
  float ggx1 = GeometrySchlickGGX(NdotL, roughness);
  
  return ggx1 * ggx2;
}

void main() {
  // Sample PBR textures with material property fallbacks
  vec3 albedo = hasDiffuseTexture ? texture(diffuseTexture, TexCoord).rgb : baseColor;
  float materialRoughness = hasRoughnessTexture ? texture(roughnessTexture, TexCoord).r : roughness;
  float materialMetallic = hasMetallicTexture ? texture(metallicTexture, TexCoord).r : metallic;
  float ao = hasAoTexture ? texture(aoTexture, TexCoord).r : 1.0;
  
  // Simple diffuse-only rendering for debugging
  if (diffuseOnly) {
    FragColor = vec4(albedo, opacity);
    return;
  }
  
  // Calculate normal - either from normal map or vertex normal
  vec3 N;
  if (hasNormalTexture) {
    // Sample normal map and transform from tangent space to world space
    vec3 normalMapSample = texture(normalTexture, TexCoord).rgb * 2.0 - 1.0;
    
    // Create TBN matrix (Tangent, Bitangent, Normal)
    vec3 T = normalize(Tangent);
    vec3 B = normalize(Bitangent);
    vec3 N_vertex = normalize(Normal);
    mat3 TBN = mat3(T, B, N_vertex);
    
    // Transform normal from tangent space to world space
    N = normalize(TBN * normalMapSample);
  } else {
    N = normalize(Normal);
  }
  vec3 V = normalize(cameraPosition - FragPos);
  
  // Calculate F0 for fresnel
  vec3 F0 = vec3(0.04);
  F0 = mix(F0, albedo, materialMetallic);
  
  // Main light
  vec3 L1 = normalize(-lightDirection);
  vec3 H1 = normalize(V + L1);
  float NdotL1 = max(dot(N, L1), 0.0);
  
  // Fill light
  vec3 L2 = normalize(-fillLightDirection);
  vec3 H2 = normalize(V + L2);
  float NdotL2 = max(dot(N, L2), 0.0);
  
  // Calculate BRDF for main light
  vec3 F1 = fresnelSchlick(max(dot(H1, V), 0.0), F0);
  float NDF1 = DistributionGGX(N, H1, materialRoughness);
  float G1 = GeometrySmith(N, V, L1, materialRoughness);
  vec3 numerator1 = NDF1 * G1 * F1;
  float denominator1 = 4.0 * max(dot(N, V), 0.0) * NdotL1 + 0.0001;
  vec3 specular1 = numerator1 / denominator1;
  
  // Toned down specular boost for less harsh highlights
  specular1 *= 1.1;
  
  // Calculate BRDF for fill light
  vec3 F2 = fresnelSchlick(max(dot(H2, V), 0.0), F0);
  float NDF2 = DistributionGGX(N, H2, materialRoughness);
  float G2 = GeometrySmith(N, V, L2, materialRoughness);
  vec3 numerator2 = NDF2 * G2 * F2;
  float denominator2 = 4.0 * max(dot(N, V), 0.0) * NdotL2 + 0.0001;
  vec3 specular2 = numerator2 / denominator2;
  
  // Toned down specular boost for less harsh highlights
  specular2 *= 1.1;
  
  vec3 kS1 = F1;
  vec3 kD1 = vec3(1.0) - kS1;
  kD1 *= 1.0 - materialMetallic;
  vec3 diffuse1 = kD1 * albedo / 3.14159265359;
  
  vec3 kS2 = F2;
  vec3 kD2 = vec3(1.0) - kS2;
  kD2 *= 1.0 - materialMetallic;
  vec3 diffuse2 = kD2 * albedo / 3.14159265359;
  
  // Ambient lighting with AO - much more subtle to let normal maps show through
  vec3 ambient = vec3(0.03) * albedo * ao;
  
  // HDRI Environment reflections for realistic lighting
  vec3 R = reflect(-V, N);
  
  vec3 environmentReflection;
  if (hasEnvironmentMap) {
    // Sample HDRI environment map
    environmentReflection = texture(environmentMap, R).rgb;
    
    // Apply roughness-based blur for more realistic reflections
    float roughnessLOD = materialRoughness * 8.0; // 8 mip levels
    environmentReflection = textureLod(environmentMap, R, roughnessLOD).rgb;
  } else {
    // Fallback to procedural environment
    vec3 skyColor = vec3(0.6, 0.6, 0.6);  // Neutral sky
    vec3 groundColor = vec3(0.1, 0.1, 0.05);  // Dark ground
    vec3 horizonColor = vec3(0.45, 0.45, 0.45);  // Neutral horizon
    
    if (R.y > 0.0) {
      environmentReflection = mix(horizonColor, skyColor, R.y);
    } else {
      environmentReflection = mix(groundColor, horizonColor, -R.y);
    }
  }
  
  // Enhanced fresnel with better falloff
  vec3 F_env = fresnelSchlick(max(dot(N, V), 0.0), F0);
  
  // Add rim lighting effect for more pop
  float rimFactor = 1.0 - max(dot(N, V), 0.0);
  rimFactor = pow(rimFactor, 2.0);
  vec3 rimLight = vec3(0.2) * rimFactor * (1.0 - materialRoughness);
  
  vec3 environment = environmentReflection * F_env * (1.0 - materialRoughness) * 0.5 + rimLight;
  
  // Add subsurface scattering for more realistic materials
  vec3 subsurface = albedo * 0.05 * max(0.0, -dot(N, L1)) * lightColor * lightIntensity;
  
  // Enhanced material response - make metals more metallic
  vec3 enhancedSpecular1 = specular1;
  vec3 enhancedSpecular2 = specular2;
  if (materialMetallic > 0.5) {
    // Boost specular for metallic materials
    enhancedSpecular1 *= (1.0 + materialMetallic);
    enhancedSpecular2 *= (1.0 + materialMetallic);
  }
  
  // Add micro-details with a subtle noise effect
  float noise = sin(FragPos.x * 50.0) * sin(FragPos.y * 50.0) * sin(FragPos.z * 50.0);
  noise = noise * 0.02 + 0.98; // Subtle variation
  vec3 microDetails = vec3(noise);
  
  // Combine all lighting with enhanced effects
  vec3 color = (ambient + subsurface) * microDetails + 
               (diffuse1 + enhancedSpecular1) * lightColor * lightIntensity * NdotL1 +
               (diffuse2 + enhancedSpecular2) * fillLightColor * fillLightIntensity * NdotL2 * 0.8 +
               environment +  // Add environment reflections
               emissive;  // Add emissive lighting
  
  // Enhanced tone mapping for more dramatic results
  // Reinhard tone mapping with slight modification for more contrast
  vec3 reinhard = color / (color + vec3(1.0));
  
  // Remove extra contrast boost to avoid brightening
  vec3 contrastBoost = reinhard;
  
  // Enhanced gamma correction
  color = pow(contrastBoost, vec3(1.0/2.2));
  
  // Slight desaturation to reduce color cast
  float luminance = dot(color, vec3(0.299, 0.587, 0.114));
  color = mix(vec3(luminance), color, 0.9);
  
  FragColor = vec4(color, 1.0);
}
