#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec2 TexCoord1;
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
uniform bool showTextureDebug;  // Output baseColorTexture.rgb in opaque pass
uniform bool showUVDebug;  // Output fract(uv) for UV visualization
uniform bool showUVRaw;  // Output raw uv for UV visualization
uniform int baseColorTexCoord;  // Base color texCoord index (0 or 1)
uniform bool missingTexcoord0;  // True when TEXCOORD_0 is missing but required
uniform bool useHairCardMode;  // Toggle hair card mode (hair cards default to dither, this allows disabling)
uniform bool isDoubleSided;  // Material is double-sided (identifies hair cards)
uniform bool useAlphaHash;  // Use alpha-hashed dither for cutoutCoverage (automatic classification)
uniform bool isOverlayBlend;  // OverlayBlend mode (makeup/decals/eyebrows) - never discard/dither, just blend
uniform int renderModeId;  // CPU renderMode: 0=opaque, 1=cutoutCoverage, 2=overlayBlend, 3=translucent
uniform float cutoutThreshold;  // Cutout threshold for CutoutCoverage mode
uniform bool showFinalAlpha;  // Output finalAlpha as grayscale
uniform bool showClassification;  // Flat colors by renderMode: Opaque=gray, OverlayBlend=cyan, CutoutCoverage=magenta, TrueBlend=yellow
uniform bool useAlphaToCoverage;  // Use GL_SAMPLE_ALPHA_TO_COVERAGE (MSAA) instead of Bayer dither for cutout materials
uniform bool debugForceTransparentColor;  // Temporary debug: force cyan with 0.5 alpha for transparent pass

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
uniform float opacity;  // baseColorFactor.a (from PBR baseColorFactor)

// Alpha mode handling
uniform int alphaMode;  // 0=OPAQUE, 1=MASK, 2=BLEND
uniform float alphaCutoff;  // For MASK mode

// Lighting uniforms
uniform vec3 lightDirection;
uniform vec3 lightColor;
uniform float lightIntensity;
uniform vec3 fillLightDirection;
uniform vec3 fillLightColor;
uniform float fillLightIntensity;
uniform vec3 cameraPosition;

// Shadow map uniforms
// Use sampler2DShadow for depth textures, but we're doing manual PCF so use sampler2D
uniform sampler2D shadowMap;
uniform bool hasShadowMap;
uniform mat4 lightSpaceMatrix;
uniform bool isShadowCatcher;  // If true, only render shadows (make base material transparent)
uniform float shadowIntensity;  // How strong shadows are (0.0 = no shadows, 1.0 = full shadows)
uniform bool shadowCatcherDebugColor;  // Debug: render shadow catchers as solid color

// Shadow calculation function
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
  
  // Get closest depth from light's perspective
  // Note: If using GL_TEXTURE_COMPARE_MODE, texture() returns comparison result (0 or 1)
  // Otherwise, it returns the depth value directly
  float closestDepth = texture(shadowMap, projCoords.xy).r;
  
  // Get current depth
  float currentDepth = projCoords.z;
  
  // DEBUG: If shadow map is all white (1.0 = far plane), return 0.0 (no shadow)
  // But also check if currentDepth is valid
  if (closestDepth >= 0.999 || currentDepth >= 0.999) {
    return 0.0; // Shadow map not initialized or nothing rendered, assume lit
  }
  
  // Check if current fragment is in shadow
  // Add bias to prevent shadow acne
  float bias = max(0.05 * (1.0 - dot(normal, lightDir)), 0.005);
  
  // Shadow calculation:
  // - closestDepth: depth of closest object from light's perspective (from shadow map)
  // - currentDepth: depth of current fragment from light's perspective
  // - If currentDepth > closestDepth, something is between us and the light = shadowed
  // - We add bias to prevent shadow acne (self-shadowing artifacts)
  float shadow = 0.0;
  vec2 texelSize = 1.0 / textureSize(shadowMap, 0);
  for (int x = -1; x <= 1; ++x) {
    for (int y = -1; y <= 1; ++y) {
      vec2 offset = vec2(x, y) * texelSize;
      float pcfDepth = texture(shadowMap, projCoords.xy + offset).r;
      // If current depth (minus bias) is greater than closest depth, we're in shadow
      shadow += (currentDepth - bias > pcfDepth) ? 1.0 : 0.0;
    }
  }
  shadow /= 9.0;
  
  return shadow;
}

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
  if (missingTexcoord0) {
    FragColor = vec4(1.0, 0.0, 0.0, 1.0);
    return;
  }
  vec2 baseUV = (baseColorTexCoord == 1) ? TexCoord1 : TexCoord;
  
  // Sample PBR textures with material property fallbacks
  // Always sample baseColorTexture as RGBA to preserve alpha channel
  vec4 baseColorTextureSample = hasDiffuseTexture ? texture(diffuseTexture, baseUV) : vec4(1.0, 1.0, 1.0, 1.0);
  
  // Compute albedo: baseColorFactor.rgb * baseColorTexture.rgb
  // Do NOT multiply RGB by alpha - alpha is only for transparency control
  vec3 albedo = baseColor * baseColorTextureSample.rgb;
  
  // Compute finalAlpha = baseColorFactor.a * baseColorTexture.a
  // This is used ONLY for transparency control (MASK discard / BLEND blending / OverlayBlend blending)
  float finalAlpha = opacity * baseColorTextureSample.a;
  
  // Debug visualizations (early return)
  if (showFinalAlpha) {
    FragColor = vec4(vec3(finalAlpha), 1.0);
    return;
  }
  
  if (showClassification) {
    // Flat colors by CPU renderMode (not alphaMode - glTF often marks opaque as BLEND with alpha=1.0)
    // renderModeId: 0=opaque, 1=cutoutCoverage, 2=overlayBlend, 3=translucent
    if (renderModeId == 0) {
      FragColor = vec4(0.5, 0.5, 0.5, 1.0);  // Gray for Opaque
      return;
    } else if (renderModeId == 1) {
      FragColor = vec4(1.0, 0.0, 1.0, 1.0);  // Magenta for CutoutCoverage
      return;
    } else if (renderModeId == 2) {
      FragColor = vec4(0.0, 1.0, 1.0, 1.0);  // Cyan for OverlayBlend
      return;
    } else if (renderModeId == 3) {
      FragColor = vec4(1.0, 1.0, 0.0, 1.0);  // Yellow for Translucent
      return;
    } else {
      FragColor = vec4(0.5, 0.5, 0.5, 1.0);  // Gray fallback
      return;
    }
  }

  if (showUVRaw) {
    FragColor = vec4(baseUV, 0.0, 1.0);
    return;
  }

  if (showUVDebug) {
    FragColor = vec4(fract(baseUV), 0.0, 1.0);
    return;
  }
  
  // Opaque pass: no discard or blending logic here.
  
  float materialRoughness = hasRoughnessTexture ? texture(roughnessTexture, TexCoord).r : roughness;
  float materialMetallic = hasMetallicTexture ? texture(metallicTexture, TexCoord).r : metallic;
  float ao = hasAoTexture ? texture(aoTexture, TexCoord).r : 1.0;
  
  
  // Simple diffuse-only rendering for debugging
  if (diffuseOnly) {
    // For OPAQUE mode, output alpha = 1.0 (ignore finalAlpha)
    // For MASK/BLEND modes, use finalAlpha
    float outputAlpha = (alphaMode == 0) ? 1.0 : finalAlpha;
    FragColor = vec4(albedo, outputAlpha);
    return;
  }
  
  // Debug mode: output baseColorTexture.rgb directly to verify texture binding
  if (showTextureDebug) {
    vec3 textureColor = hasDiffuseTexture ? baseColorTextureSample.rgb : vec3(0.5, 0.5, 0.5);
    FragColor = vec4(textureColor, 1.0);
    return;
  }
  
  
  vec3 V = normalize(cameraPosition - FragPos);
  
  // Calculate normal (opaque pass always uses normal maps when available)
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
  
  // Calculate F0 for fresnel
  // For CutoutCoverage hair cards, kill specular to avoid bright white streaks
  // OverlayBlend must NEVER suppress specular (coverage vs blend separation)
  vec3 F0 = (useAlphaHash && alphaMode == 2 && !isOverlayBlend) ? vec3(0.0) : vec3(0.04);
  F0 = mix(F0, albedo, materialMetallic);
  
  // Main light
  vec3 L1 = normalize(-lightDirection);
  vec3 H1 = normalize(V + L1);
  float NdotL1 = max(dot(N, L1), 0.0);
  
  // Calculate shadow factor for main light
  // Apply shadow intensity to make shadows lighter
  float rawShadow = calculateShadow(FragPos, N, L1);
  float shadowFactor = 1.0 - (rawShadow * shadowIntensity);
  
  // Store rawShadow for shadow catchers (they need full shadow intensity)
  float shadowForCatchers = rawShadow;
  
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
  
  // CutoutCoverage: kill specular for hair cards (only CutoutCoverage, not OverlayBlend)
  if (useAlphaHash && alphaMode == 2 && !isOverlayBlend) {
    // No specular highlights for CutoutCoverage hair cards
    specular1 = vec3(0.0);
    specular2 = vec3(0.0);
  }
  
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
  // CutoutCoverage: kill environment reflections for hair cards (only CutoutCoverage, not OverlayBlend)
  if (useAlphaHash && alphaMode == 2 && !isOverlayBlend) {
    // CutoutCoverage hair cards should not reflect the environment (looks like white paint strokes)
    environment = vec3(0.0);
  }
  
  // Add subsurface scattering for more realistic materials
  vec3 subsurface = albedo * 0.05 * max(0.0, -dot(N, L1)) * lightColor * lightIntensity;
  // CutoutCoverage: kill subsurface for hair cards (only CutoutCoverage, not OverlayBlend)
  if (useAlphaHash && alphaMode == 2 && !isOverlayBlend) {
    // No subsurface for CutoutCoverage hair cards
    subsurface = vec3(0.0);
  }
  
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
  // Apply shadow factor to main light (diffuse and specular)
  // Normal rendering (shadow catchers already handled above with early return)
  vec3 color = (ambient + subsurface) * microDetails + 
               (diffuse1 + enhancedSpecular1) * lightColor * lightIntensity * NdotL1 * shadowFactor +
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
  
  // Opaque pass: always output alpha = 1.0 for proper depth testing
  FragColor = vec4(color, 1.0);
}
