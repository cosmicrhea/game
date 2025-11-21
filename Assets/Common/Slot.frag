#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform vec2 uResolution;
uniform vec2 uPanelSize;
uniform vec2 uPanelCenter;
uniform float uBorderThickness;
uniform float uCornerRadius;
uniform float uNoiseScale;
uniform float uNoiseStrength;
uniform float uRadialGradientStrength;
uniform float uPulse; // 0.0 disabled, 1.0 enabled

// Optional time (provided by GLScreenEffect if present)
uniform float iTime;

// Optional border tinting (applied only to the border)
uniform vec3 uBorderTint;
uniform float uBorderTintStrength; // 0..1

// Equipped inner stroke (drawn just inside the inner border)
uniform float uEquippedStroke; // 0.0 disabled, 1.0 enabled
uniform vec3 uEquippedStrokeColor;
uniform float uEquippedStrokeWidth; // pixels (e.g., 4.0-5.0)

// Equipped inner glow (radial glow from center)
uniform float uEquippedGlow; // 0.0 disabled, 1.0 enabled
uniform vec3 uEquippedGlowColor;
uniform float uEquippedGlowStrength; // 0..1

// Colors
uniform vec3 uPanelColor;
uniform float uPanelAlpha; // Panel alpha multiplier (0.0-1.0), defaults to 1.0
uniform vec3 uBorderColor;
uniform vec3 uBorderHighlight;
uniform vec3 uBorderShadow;

// Noise function for texture
float random(vec2 st) {
  return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

float noise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);

  float a = random(i);
  float b = random(i + vec2(1.0, 0.0));
  float c = random(i + vec2(0.0, 1.0));
  float d = random(i + vec2(1.0, 1.0));

  vec2 u = f * f * (3.0 - 2.0 * f);

  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Rounded rectangle SDF
float roundedBoxSDF(vec2 centerPos, vec2 size, float radius) {
  vec2 q = abs(centerPos) - size + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
  vec2 uv = TexCoord * uResolution;
  vec2 center = uPanelCenter;
  vec2 halfSize = uPanelSize * 0.5;

  // Calculate distance to panel edge
  float distance = roundedBoxSDF(uv - center, halfSize, uCornerRadius);

  // Main panel area
  float panelMask = 1.0 - smoothstep(0.0, 1.0, distance);

  // Border layers - create multiple border layers for depth
  float borderOuter = 1.0 - smoothstep(0.0, 1.0, distance);
  float borderInner =
      1.0 - smoothstep(uBorderThickness - 1.0, uBorderThickness, distance);
  float borderMask = borderOuter - borderInner;

  // Inner shadow - create inset effect
  float innerShadowDistance =
      roundedBoxSDF(uv - center, halfSize - vec2(4.0), uCornerRadius - 2.0);
  float innerShadow = 1.0 - smoothstep(0.0, 3.0, innerShadowDistance);
  innerShadow *= panelMask; // Only inside panel

  // Radial gradient from center
  vec2 toCenter = (uv - center) / halfSize;
  float radialDist = length(toCenter);
  float radialGradient = 1.0 - smoothstep(0.0, 0.8, radialDist);

  // Create sophisticated border with multiple layers
  vec2 borderUV = (uv - center) / halfSize;
  float borderGradient = 0.0;

  if (borderMask > 0.0) {
    // Silver-ish metallic border with multiple highlights
    vec2 lightDir1 = normalize(vec2(-1.0, -1.0)); // Main light
    vec2 lightDir2 = normalize(vec2(-0.7, -0.3)); // Secondary light
    float lightDot1 = dot(normalize(borderUV), lightDir1);
    float lightDot2 = dot(normalize(borderUV), lightDir2);

    // Create metallic highlight bands
    float highlight1 = pow(max(0.0, lightDot1), 2.0);
    float highlight2 = pow(max(0.0, lightDot2), 3.0) * 0.6;

    borderGradient = highlight1 + highlight2;
    borderGradient = mix(0.2, 1.0, borderGradient);
  }

  // Add noise texture only to border area
  float noiseValue = noise(uv * uNoiseScale) * uNoiseStrength;
  float borderNoise = noiseValue * borderMask;

  // Panel color with radial gradient and inner shadow
  vec3 panelColor = uPanelColor;
  // Apply radial gradient - more visible effect
  if (uRadialGradientStrength > 0.0) {
    panelColor *= (0.7 + 0.3 * uRadialGradientStrength * radialGradient);
  } else {
    panelColor *= 0.6;
  }
  panelColor *= (0.8 + 0.2 * (1.0 - innerShadow)); // Inner shadow effect


  // Silver-ish border with metallic appearance
  vec3 silverBase = vec3(0.6, 0.65, 0.7);      // Silver base color
  vec3 silverHighlight = vec3(0.9, 0.95, 1.0); // Bright silver highlight
  vec3 silverShadow = vec3(0.3, 0.35, 0.4);    // Dark silver shadow

  vec3 borderColor = mix(silverShadow, silverBase, borderGradient);
  borderColor = mix(borderColor, silverHighlight, borderGradient * 0.5);
  borderColor += borderNoise * 0.15; // More pronounced noise in border

  // Add subtle rim lighting
  float rimLight = 1.0 - smoothstep(0.0, 2.0, abs(distance));
  borderColor += vec3(0.1, 0.12, 0.15) * rimLight * borderMask;

  // Apply optional border tint
  borderColor =
      mix(borderColor, uBorderTint, clamp(uBorderTintStrength, 0.0, 1.0));

  // Combine colors
  vec3 finalColor = mix(panelColor, borderColor, borderMask);

  // Equipped inner glow (ring around the inner edge, inside the slot)
  if (uEquippedGlow > 0.0) {
    // Calculate distance to the slot edge
    float edgeDist = roundedBoxSDF(uv - center, halfSize, uCornerRadius);
    // Create an inner edge ring - draw just inside the border
    // Use a smaller size to draw inside the slot
    float innerOffset = uEquippedGlowStrength * 3.0; // Offset from edge in pixels
    float innerRadius = max(0.0, uCornerRadius - innerOffset);
    vec2 innerHalfSize = max(halfSize - vec2(innerOffset), vec2(1.0));
    float innerEdgeDist = roundedBoxSDF(uv - center, innerHalfSize, innerRadius);
    // Create a ring mask - band around the inner edge
    float ringWidth = 2.0; // Width of the inner edge ring
    float glowMask = smoothstep(ringWidth, 0.0, abs(innerEdgeDist));
    // Only apply inside the slot (where edgeDist < 0)
    glowMask *= step(edgeDist, 0.0);
    // Apply the glow
    finalColor = mix(finalColor, uEquippedGlowColor,
                     clamp(glowMask * uEquippedGlow, 0.0, 1.0));
  }

  // Equipped stroke (drawn exactly on the edge)
  if (uEquippedStroke > 0.0) {
    // Calculate distance to the slot edge
    float edgeDist = roundedBoxSDF(uv - center, halfSize, uCornerRadius);
    // Draw exactly on the edge - centered on the edge (half inside, half outside)
    // The stroke will be half inside and half outside the slot
    float strokeMask = smoothstep(uEquippedStrokeWidth * 0.5, 0.0, abs(edgeDist));
    // Make it more prominent by using full strength
    finalColor = mix(finalColor, uEquippedStrokeColor,
                     clamp(strokeMask * uEquippedStroke, 0.0, 1.0));
  }

  // Subtle pulsing multiplier when enabled
  float pulseAmount = 0.06; // ~±6%
  float pulse = 1.0 + uPulse * pulseAmount * sin(iTime * 3.2);
  finalColor *= pulse;

  // Add subtle vignette to central area
  if (uRadialGradientStrength > 0.0) {
    float vignette =
        1.0 - smoothstep(0.0, length(halfSize) * 0.9, length(uv - center));
    vignette = mix(0.9, 1.0, vignette);
    finalColor *= vignette;
  }

  // Apply panel mask with alpha multiplier
  float alpha = panelMask * uPanelAlpha;

  FragColor = vec4(finalColor, alpha);
}
