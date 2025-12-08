#version 330 core
in vec2 TexCoord;
out vec4 FragColor;

uniform sampler2D uTexture;
uniform vec2 uResolution;
uniform float iTime;
uniform float amount; // Effect strength (0.0 = no effect, 1.0 = full effect)

// Simple hash for noise
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth noise
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal brownian motion for organic shapes
float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  float frequency = 1.0;
  
  for (int i = 0; i < 5; i++) {
    value += amplitude * noise(p * frequency);
    frequency *= 2.0;
    amplitude *= 0.5;
  }
  return value;
}

// Blood splatter shape
float bloodSplatter(vec2 uv, vec2 center, float size) {
  vec2 offset = uv - center;
  float dist = length(offset);
  
  // Create organic shape using noise
  float angle = atan(offset.y, offset.x);
  float noiseVal = fbm(vec2(angle * 3.0, dist * 5.0) + center * 10.0);
  
  // Make dripping effect
  float drip = max(0.0, (center.y - uv.y) * 2.0) * noise(vec2(uv.x * 20.0, 0.0));
  
  // Create the splatter shape
  float radius = size * (0.5 + noiseVal * 0.5);
  float splatter = smoothstep(radius, radius * 0.3, dist - drip * 0.3);
  
  return splatter;
}

void main() {
  vec2 uv = TexCoord;
  
  // Sample the input texture (captured screen)
  vec4 texColor = texture(uTexture, TexCoord);
  
  // Dark vignette from the center
  vec2 center = vec2(0.5, 0.5);
  float distFromCenter = length(uv - center);
  float vignette = 1.0 - smoothstep(0.2, 0.9, distFromCenter);
  
  // Create multiple blood splatters on the left side
  float blood = 0.0;
  
  // Main large splatter - positioned based on screenshot
  blood = max(blood, bloodSplatter(uv, vec2(0.15, 0.55), 0.35));
  blood = max(blood, bloodSplatter(uv, vec2(0.08, 0.45), 0.25));
  blood = max(blood, bloodSplatter(uv, vec2(0.22, 0.35), 0.2));
  blood = max(blood, bloodSplatter(uv, vec2(0.05, 0.65), 0.18));
  blood = max(blood, bloodSplatter(uv, vec2(0.12, 0.25), 0.15));
  
  // Drips at bottom
  blood = max(blood, bloodSplatter(uv, vec2(0.18, 0.15), 0.12));
  blood = max(blood, bloodSplatter(uv, vec2(0.25, 0.2), 0.1));
  
  // Blood color - dark crimson red
  vec3 bloodColor = vec3(0.35, 0.05, 0.05);
  
  // Very dark greenish-gray background (like in the screenshot)
  vec3 backgroundColor = vec3(0.08, 0.09, 0.08);
  
  // Subtle noise texture on background for grit
  float bgNoise = noise(uv * 200.0) * 0.03;
  backgroundColor += vec3(bgNoise);
  
  // Horizontal scan lines effect (subtle)
  float scanline = 1.0 - abs(sin(uv.y * uResolution.y * 0.5)) * 0.02;
  
  // Mix the scene
  vec3 color = texColor.rgb;
  
  // Apply dark overlay with vignette
  color = mix(color, backgroundColor, amount * (0.85 + (1.0 - vignette) * 0.15));
  
  // Apply blood splatters
  color = mix(color, bloodColor, blood * amount * 0.9);
  
  // Apply scanlines
  color *= mix(1.0, scanline, amount * 0.5);
  
  // Subtle pulsing on the blood (very slow, barely visible)
  float pulse = sin(iTime * 0.5) * 0.02 + 1.0;
  color = mix(color, color * pulse, blood * amount * 0.3);
  
  FragColor = vec4(color, texColor.a);
}

