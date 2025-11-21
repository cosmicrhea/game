#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform vec2 uResolution;
uniform vec2 uRectCenter;
uniform vec2 uRectSize;
uniform float uCornerRadius;
uniform float uRingThickness;
uniform float uGlowThickness;
uniform float uRingAlpha;
uniform float uGlowAlpha;
uniform vec3 uRingColor;
uniform vec3 uGlowColor;
uniform float uPulseStrength;
uniform float uNoiseStrength;
uniform float uIsInside;

uniform float iTime;

float hash21(vec2 p) {
  p = fract(p * vec2(234.34, 435.345));
  p += dot(p, p + 34.23);
  return fract(p.x * p.y);
}

float roundedBoxSDF(vec2 pos, vec2 halfSize, float radius) {
  vec2 q = abs(pos) - halfSize + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
  vec2 uv = TexCoord * uResolution;
  vec2 halfSize = max(uRectSize * 0.5, vec2(1.0));
  float distance = roundedBoxSDF(uv - uRectCenter, halfSize, uCornerRadius);

  float ringMask = 0.0;
  float glowMask = 0.0;

  if (uIsInside > 0.5) {
    // Inner shadow/glow: draw from the edge inward
    if (distance > 0.0) {
      discard;
    }
    float innerDistance = -distance;  // positive inside
    ringMask = smoothstep(uRingThickness, 0.0, innerDistance);
    glowMask = smoothstep(uRingThickness + uGlowThickness, uRingThickness, innerDistance);
  } else {
    // Outer glow: draw from the edge outward
    if (distance < 0.0) {
      discard;
    }
    float outerDistance = distance;  // positive outside
    ringMask = smoothstep(0.0, uRingThickness, outerDistance);
    float glowStart = uRingThickness;
    float glowEnd = uRingThickness + max(0.5, uGlowThickness);
    glowMask = smoothstep(glowStart, glowEnd, outerDistance);
  }

  // Procedural noise for subtle shimmer (slowed down 15x)
  float noiseSample = hash21(uv * 0.35 + iTime * 0.01);
  float noiseFactor = 1.0 + (noiseSample - 0.5) * uNoiseStrength;

  float pulse = 1.0 + sin(iTime * 2.2) * uPulseStrength;

  float ringAlpha = ringMask * uRingAlpha * pulse * noiseFactor;
  float glowAlpha = glowMask * uGlowAlpha * pulse;

  float alpha = ringAlpha + glowAlpha;
  if (alpha <= 0.001) {
    discard;
  }

  vec3 color = vec3(0.0);
  if (alpha > 0.0) {
    vec3 accumulated = uRingColor * ringAlpha + uGlowColor * glowAlpha;
    color = accumulated / alpha;
  }

  FragColor = vec4(color, alpha);
}


