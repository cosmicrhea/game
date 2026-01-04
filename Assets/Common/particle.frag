#version 330 core

in vec4 vColor;
in vec2 vUV;

out vec4 FragColor;

uniform sampler2D particleTexture;
uniform bool hasTexture;

void main() {
  vec4 finalColor = vColor;
  
  if (hasTexture) {
    // Sample texture and multiply by particle color
    vec4 texColor = texture(particleTexture, vUV);
    finalColor.rgb *= texColor.rgb;
    finalColor.a *= texColor.a;
  } else {
    // Fallback: simple circular falloff for smoother edges
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(vUV, center);
    float alpha = vColor.a;
    
    // Soft edge falloff
    float edgeFalloff = 0.3;
    if (dist > 0.5 - edgeFalloff) {
      float edgeFactor = (0.5 - dist) / edgeFalloff;
      alpha *= smoothstep(0.0, 1.0, edgeFactor);
    }
    
    // Discard pixels outside circle
    if (dist > 0.5) {
      discard;
    }
    
    finalColor.a = alpha;
  }
  
  FragColor = finalColor;
}

