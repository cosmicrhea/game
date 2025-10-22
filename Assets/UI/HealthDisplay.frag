// Engine-compatible variant: uses GLScreenEffect passthrough vertex which outputs TexCoord
#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D uTexture; // captured backbuffer
uniform vec2 uResolution;   // viewport size in pixels

uniform float health;       // 1.0 (full) → 0.0 (dead)
uniform float iTime;        // time in seconds (provided by engine)
// Use iTime provided by engine
uniform vec3 iResolution;   // (w, h, 1)
uniform vec2 uRectSize;     // provided by host (same as resolution)
uniform vec2 uRectCenter;   // center position in pixels
uniform float uThickness;   // line thickness multiplier (in screen-space via fwidth)
uniform float uBgDim;       // background dim factor (0=no dim, 1=black)
uniform float uBgAlpha;     // how strongly to apply dim within rect [0,1]
uniform float uSpikeAmp;    // spike amplitude (0..1)
uniform float uSpikeFreq;   // spikes per circle (e.g., 120)
uniform float uSpikeThreshold; // only positive excursions above this create spikes (0..1)
uniform float uGlow;        // additive halo strength
uniform float uDangerArc;   // fraction of the circle to mark as danger (0..0.5)
uniform float uRadius;      // base ring radius in normalized space [0,1]
uniform float uSpikeLen;    // outward spike length scale
uniform float uGlowRadius;  // halo thickness control (normalized)
uniform float uInnerAlpha;  // inner haze intensity

// simple hash for noise
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void main() {
    // Base scene underlay
    vec2 fragCoord = gl_FragCoord.xy;
    vec4 baseColor = texture(uTexture, fragCoord / uResolution);

    // Local coords relative to rect, mapped to -1..1 inside the rect
    vec2 halfSize = uRectSize * 0.5;
    vec2 p = (fragCoord - uRectCenter) / max(halfSize, vec2(1.0));
    float r = length(p);
    float a = atan(p.y, p.x);            // [-pi, pi]
    float an = (a + 3.14159265) / (2.0 * 3.14159265); // [0,1]

    float t = iTime;

    // pulse animation
    float pulse = sin(t * 3.0) * 0.05 + 1.0;

    // Base ring radius in normalized space
    float baseRadius = clamp(uRadius, 0.45, 0.9);

    // Angular noise for choppy outline and spikes (only outward)
    float n = noise(vec2(an * uSpikeFreq, t * 0.7));
    float spike = max(0.0, (n - uSpikeThreshold)) * (uSpikeAmp);
    float targetRadius = baseRadius + spike * uSpikeLen; // scale spikes outward

    // Ring band with analytic AA
    float band = abs(r - targetRadius);
    float width = fwidth(band) * max(1.0, uThickness);
    float ring = 1.0 - smoothstep(0.0, width, band);

    // distortion: more cracks at low health
    float distortion = noise(p * (6.0 + (1.0 - health) * 12.0) + t * 0.5);
    ring *= 1.0 - distortion * (1.0 - health) * 0.7;

    // Fixed radial alpha (no health-based fade)
    float alpha = smoothstep(0.0, 0.3, 1.0 - r);

    // color shifts from cyan → red on a danger arc proportion near the right side
    float dangerMask = step(1.0 - clamp(uDangerArc, 0.0, 0.5), an);
    vec3 baseCyan = vec3(0.68, 0.90, 0.97);
    vec3 dangerRed = vec3(1.0, 0.25, 0.20);
    vec3 color = mix(baseCyan, dangerRed, dangerMask * (1.0 - health));
    color *= ring;

    // add flicker near death
    float flicker = step(0.1, fract(sin(t * 40.0) * 43758.5453));
    if (health < 0.25 && flicker > 0.5)
        color *= 1.2 + sin(t * 50.0) * 0.3;

    // Constrain strictly to the rect
    float inside = 1.0 - step(1.0, max(abs(p.x), abs(p.y)));
    float ringAlpha = alpha * inside;

    // Translucent background: softly dim base under the effect instead of black
    float dimAmount = (alpha * uBgAlpha) * inside; // stronger toward center
    vec3 darkenedBase = mix(baseColor.rgb, baseColor.rgb * uBgDim, dimAmount);

    // Additive halo around the ring
    float glow = smoothstep(uGlowRadius, 0.0, band) * uGlow * inside;

    // Inner haze to avoid a dead void in the middle (strictly inside ring and rect)
    float innerMask = 1.0 - smoothstep(targetRadius - 0.35, targetRadius, r);
    float innerNoise = noise(p * 12.0 + vec2(t * 0.6, -t * 0.5));
    vec3 innerColor = mix(baseCyan * 0.08, baseCyan * 0.25, innerNoise)
                    * (uInnerAlpha * innerMask * inside);

    vec3 outRGB = darkenedBase + innerColor + color * ringAlpha + mix(vec3(0.0), baseCyan, 0.7) * glow;
    FragColor = vec4(outRGB, 1.0);
}