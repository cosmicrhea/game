// https://www.shadertoy.com/view/ftGXzK

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  // Normalized pixel coordinates (from 0 to 1)
  vec2 uv = fragCoord/iResolution.xy;

  // Make a vignette in the middle of the screen
  float d = length(uv-vec2(0.5,0.5));
  float c = 1.0-d;
  vec3 red = vec3(sin(iTime*2.0)/10.0+0.1,0.0,0.0);

  // Output to screen
  fragColor = vec4(vec3(c)+(red/c),1.0);
}
