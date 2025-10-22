// Shadertoy-style shader (wrapped by engine):
// Uses iResolution (vec3), iTime, iChannel0 and mainImage(out, in)

// Rect region
uniform vec2 uRectCenter;     // pixels
uniform vec2 uRectSize;       // pixels

// ECG controls
uniform float health;         // 0..1
uniform float uGridAlpha;     // 0..1
uniform float uGlow;          // 0..1
uniform float uLineWidth;     // px-like

// Frosted glass panel controls
uniform float uBgDim;         // 0..1 darken inside panel
uniform float uBgAlpha;       // 0..1 panel influence strength
uniform float uCorner;        // px corner radius
uniform float uEdgeSoftness;  // px soft edge
uniform float uBorderThickness; // px
uniform float uBorderSoftness;  // px
uniform vec3 uPanelTint;      // RGB tint for panel
uniform vec3 uBorderColor;    // RGB color for border

// Frost spikes/band along rectangular border
uniform float uFrostThickness;  // band thickness multiplier
uniform float uGlowRadius;      // halo falloff control
uniform float uSpikeAmp;        // 0..1
uniform float uSpikeFreq;       // spikes per edge
uniform float uSpikeThreshold;  // 0..1
uniform float uSpikeLenPx;      // inward spike offset in pixels
uniform float uPanelInsetPx;    // shrink panel inside rect to leave outer margin

// Helpers
float hash(float n) { return fract(sin(n) * 43758.5453); }
float noise1(float x) {
  float i = floor(x);
  float f = fract(x);
  float u = f * f * (3.0 - 2.0 * f);
  return mix(hash(i), hash(i + 1.0), u);
}

float hash2D(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float noise2D(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  float a = hash2D(i);
  float b = hash2D(i + vec2(1.0, 0.0));
  float c = hash2D(i + vec2(0.0, 1.0));
  float d = hash2D(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Rounded box SDF (p in pixels, b = halfSize in pixels)
float roundedBoxSDF(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 halfSize = uRectSize * 0.5;
  vec2 p = fragCoord - uRectCenter;        // pixel space centered in rect
  vec2 uv = p / max(halfSize, vec2(1.0));  // -1..1 in rect
  vec2 uv01 = uv * 0.5 + 0.5;              // 0..1 in rect

  // Base underlay
  vec4 base = texture(iChannel0, fragCoord / iResolution.xy);

  // Outer rect mask (for any effects that extend beyond panel)
  float outerInside = step(abs(uv.x), 1.0) * step(abs(uv.y), 1.0);

  // Panel SDF and masks (inset to create margin for frost/spikes)
  float cornerPx = max(0.0, uCorner - uPanelInsetPx);
  vec2 halfSizePanel = max(vec2(1.0), halfSize - vec2(uPanelInsetPx));
  float sdf = roundedBoxSDF(p, halfSizePanel - vec2(0.5), cornerPx);
  float edgeAlpha = 1.0 - smoothstep(0.0, max(0.0001, uEdgeSoftness), sdf);
  float borderBand = 1.0 - smoothstep(
    uBorderThickness - uBorderSoftness,
    uBorderThickness,
    abs(sdf)
  );
  float inside = step(sdf, 0.0);

  // Subtle grid (horizontal lines)
  float gridY = fract(uv01.y * 10.0);
  float gridLine = smoothstep(0.0, 0.01, gridY) * (1.0 - smoothstep(0.98, 1.0, gridY));
  vec3 gridCol = vec3(1.0, 0.85, 0.25) * 0.35;

  float t = iTime;

  // Color based on health zone
  vec3 okCol = vec3(0.65, 0.88, 0.95);
  vec3 cautionCol = vec3(0.95, 0.72, 0.25);
  vec3 fatalCol = vec3(1.0, 0.25, 0.20);
  vec3 frostCol = okCol;
  if (health < 0.50 && health >= 0.33) frostCol = cautionCol;
  if (health < 0.33) frostCol = fatalCol;

  // Frost band around rounded rect using SDF
  float band = abs(sdf);
  float width = fwidth(band) * max(1.0, uFrostThickness);

  // Perimeter coordinate tEdge for spikes
  bool vertical = abs(p.x) > abs(p.y);
  float tEdge = vertical ? (p.y + halfSizePanel.y) / (2.0 * halfSizePanel.y) : (p.x + halfSizePanel.x) / (2.0 * halfSizePanel.x);
  float n = noise1(tEdge * uSpikeFreq + t * 0.7);
  float spike = max(0.0, (n - uSpikeThreshold)) * uSpikeAmp;

  // Core frost line and additive halo
  // Shift SDF inward by spikes so spikes grow into panel (avoid clipping by outer rect)
  float bandShifted = abs((sdf - spike * uSpikeLenPx));
  float frostCore = 1.0 - smoothstep(0.0, width, bandShifted);
  float frostHalo = smoothstep(uGlowRadius, 0.0, bandShifted) * uGlow;

  // Compose base panel/frost
  vec3 col = base.rgb;
  // Frosted panel dim + tint
  float panelMix = edgeAlpha * uBgAlpha;
  col = mix(col, col * (1.0 - uBgDim) + uPanelTint * 0.15, panelMix);
  // Border
  col = mix(col, uBorderColor, min(borderBand, edgeAlpha));
  // Frost grain
  float grain = noise2D(fragCoord * 0.75 + vec2(iTime * 0.35, -iTime * 0.28));
  col += (grain - 0.5) * 0.06 * edgeAlpha;
  // Grid
  col += gridCol * gridLine * uGridAlpha * inside;
  // Frost band
  col += frostCol * (frostCore + frostHalo + spike * 0.6) * inside;

  // ECG waveform overlay (additive) — Resident Evil-style piecewise beat
  float speed = 0.6;
  float s = fract(uv01.x - t * speed);
  float ampScale = 0.6 + (1.0 - health) * 0.4;
  float P = 0.06 * exp(-pow((s - 0.16) / 0.03, 2.0));
  float Q = -0.12 * exp(-pow((s - 0.48) / 0.010, 2.0));
  float R = 1.00 * exp(-pow((s - 0.50) / 0.004, 2.0));
  float Sdip = -0.25 * exp(-pow((s - 0.52) / 0.010, 2.0));
  float T = 0.28 * exp(-pow((s - 0.78) / 0.060, 2.0));
  float jitter = (noise1(s * 24.0 + t * 0.8) - 0.5) * 0.04;
  float ecg = 0.50 + (P + Q + R + Sdip + T) * ampScale + jitter;
  float ecgYPx = mix(-halfSizePanel.y, halfSizePanel.y, ecg);
  float d = abs(p.y - ecgYPx);
  float lw = uLineWidth;
  float ecgCore = 1.0 - smoothstep(lw * 0.2, lw, d);
  float ecgHalo = 1.0 - smoothstep(lw * 1.5, lw * 4.5, d);
  vec3 lineCol = frostCol;
  col += lineCol * (ecgCore + ecgHalo * uGlow) * inside;

  fragColor = vec4(col, 1.0);
}

