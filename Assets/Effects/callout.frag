// Minimal overlay rectangle with right-side fade and only top/bottom borders
// Parametric via uniforms for position, size, colors, and fade.
// Style matches the Shadertoy-like setup used by panel.frag (iResolution, iChannel0, mainImage)

// Custom uniforms (optional - use sensible defaults if left at 0)
uniform vec2  uRectCenter;       // center position in pixels
uniform vec2  uRectSize;         // width, height in pixels
uniform vec4  uFillColor;        // rgba
uniform vec4  uBorderColor;      // rgba
uniform float uEdgeSoftness;     // pixels
uniform float uBorderThickness;  // pixels
uniform float uBorderSoftness;   // pixels
uniform float uRightFadeWidth;   // pixels
uniform float uLeftFadeWidth;    // pixels
uniform float uAnimationAlpha;    // animation progress [0,1]

// SDF for an axis-aligned box with sharp corners
float boxSDF(vec2 position, vec2 halfSize)
{
    vec2 delta = abs(position) - halfSize;
    return min(max(delta.x, delta.y), 0.0) + length(max(delta, 0.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Inputs (treated like uniforms by the engine using this file)
    // Rectangle geometry (with defaults)
    vec2  u_rectSize    = (uRectSize.x > 0.0 || uRectSize.y > 0.0) ? uRectSize : vec2(520.0, 44.0);
    vec2  u_rectCenter  = (uRectCenter.x > 0.0 || uRectCenter.y > 0.0)
                          ? uRectCenter
                          : vec2(u_rectSize.x * 0.5, iResolution.y - 17.0 - u_rectSize.y * 0.5);
    
    // Debug: hardcode the center to see if that fixes the movement
    // u_rectCenter = vec2(260.0, 518.0);

    // Visuals (defaults with uniform overrides)
    vec4  u_fillColor   = (uFillColor.a > 0.0)  ? uFillColor  : vec4(0.10, 0.10, 0.10, 0.60);
    vec4  u_borderColor = (uBorderColor.a > 0.0)? uBorderColor: vec4(1.00, 1.00, 1.00, 0.15);

    // Edge and border softness (antialiasing)
    float u_edgeSoftness    = (uEdgeSoftness     > 0.0) ? uEdgeSoftness    : 1.5;
    float u_borderThickness = (uBorderThickness  > 0.0) ? uBorderThickness : 1.0;
    float u_borderSoftness  = (uBorderSoftness   > 0.0) ? uBorderSoftness  : 0.75;

    // Fade on the right side of the rectangle (in pixels)
    float u_rightFadeWidth  = uRightFadeWidth;

    // Background (captured screen)
    vec2 uv        = fragCoord.xy / iResolution.xy;
    vec4 baseColor = texture(iChannel0, uv);

    // Derived values (using possibly overridden uniforms from host)
    vec2 halfSize = u_rectSize * 0.5;
    vec2 p        = fragCoord.xy - u_rectCenter;

    // Box alpha via SDF (sharp-corner rectangle)
    float distanceToBox = boxSDF(p, halfSize);
    float boxAlpha      = 1.0 - smoothstep(0.0, u_edgeSoftness, distanceToBox);

    // Right-side fade factor
    float distFromRight = halfSize.x - p.x; // inside the box: 0 at right edge, increases to the left
    float rightFade     = (uRightFadeWidth > 0.0) ? clamp(distFromRight / uRightFadeWidth, 0.0, 1.0) : 1.0;

    // Left-side fade factor
    float distFromLeft  = halfSize.x + p.x; // 0 at left edge, increases to the right
    float leftFade      = (uLeftFadeWidth > 0.0) ? clamp(distFromLeft / uLeftFadeWidth, 0.0, 1.0) : 1.0;

    float lateralFade = rightFade * leftFade;

    // Animation alpha (default to 1.0 if not set)
    float animationAlpha = (uAnimationAlpha > 0.0) ? uAnimationAlpha : 1.0;

    // Fill final alpha (with color alpha, right fade, and animation)
    float fillAlpha = min(u_fillColor.a, boxAlpha) * lateralFade * animationAlpha;

    // Only top and bottom borders
    // Distance to the horizontal edges (top/bottom) regardless of sign
    float distToHorizontalEdge = abs(abs(p.y) - halfSize.y);

    // Restrict borders to lie within the rectangle horizontally (with AA)
    float insideX = 1.0 - smoothstep(halfSize.x, halfSize.x + u_edgeSoftness, abs(p.x));

    // Build a thin band near the top and bottom edges
    float borderBand = 1.0 - smoothstep(
        u_borderThickness - u_borderSoftness,
        u_borderThickness,
        distToHorizontalEdge
    );

    float borderAlpha = min(u_borderColor.a, borderBand * insideX) * lateralFade * animationAlpha;

    // Layer: background -> fill -> borders
    vec4 withFill    = mix(baseColor, u_fillColor, fillAlpha);
    vec4 withBorders = mix(withFill,  u_borderColor, borderAlpha);

    fragColor = withBorders;
}


