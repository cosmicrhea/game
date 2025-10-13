// https://www.shadertoy.com/view/lsKSWR

uniform float amount; // Vignette strength (0.0 = no effect, 1.0 = full effect)

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord.xy / iResolution.xy;

  uv *= 1.0 - uv.yx; // vec2(1.0)- uv.yx; -> 1.-u.yx; Thanks FabriceNeyret !

  float vig = uv.x * uv.y * 15.0; // multiply with sth for intensity

  vig = pow(vig, 0.25); // change pow for modifying the extend of the  vignette

  // Apply amount parameter
  vig = mix(1.0, vig, amount);

  fragColor = vec4(vig);
}
