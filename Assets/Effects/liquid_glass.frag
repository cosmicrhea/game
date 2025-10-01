// https://www.shadertoy.com/view/3cKXzR
// Interactive glass lens shader with background image support
// Uses proper fresnel and refraction physics

// IQ's latest superellipse SDF design
vec3 sdSuperellipse(vec2 p, float r, float n) {
    p = p / r;
    vec2 gs = sign(p);
    vec2 ps = abs(p);
    float gm = pow(ps.x, n) + pow(ps.y, n);
    float gd = pow(gm, 1.0 / n) - 1.0;
    vec2  g = gs * pow(ps, vec2(n - 1.0)) * pow(gm, 1.0 / n - 1.0);
    p = abs(p); if (p.y > p.x) p = p.yx;
    n = 2.0 / n;
    float s = 1.0;
    float d = 1e20;
    const int num = 12;
    vec2 oq = vec2(1.0, 0.0);
    for (int i = 1; i < num; i++) {
        float h = float(i)/float(num-1);
        vec2 q = vec2(pow(cos(h * 3.1415927 / 4.0), n),
                      pow(sin(h * 3.1415927 / 4.0), n));
        vec2  pa = p - oq;
        vec2  ba = q - oq;
        vec2  z = pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float d2 = dot(z, z);
        if (d2 < d) {
            d = d2;
            s = pa.x * ba.y - pa.y * ba.x;
        }
        oq = q;
    }
    return vec3(sqrt(d) * sign(s) * r, g);
}

// Checker pattern function (fallback if no image)
float checker(vec2 uv, float scale) {
    vec2 c = floor(uv * scale);
    return mod(c.x + c.y, 2.0);
}

// Background sampling function - uses image if available, checker pattern as fallback
vec3 sampleBackground(vec2 uv) {
    // Convert UV to texture coordinates (0-1 range)
    vec2 texUV = (uv + vec2(1.0, 0.5)) / vec2(2.0, 1.0);

    // Check if we have a background image (iChannel0)
    if (iChannelResolution[0].x > 0.0) {
        // Sample from background image
        return texture(iChannel0, texUV).rgb;
    } else {
        // Fallback to checker pattern
        float checkerPattern = checker(uv, 2.0);
        return mix(vec3(0.95, 0.95, 0.95), vec3(0.1, 0.1, 0.1), checkerPattern);
    }
}

// Smooth minimum for blending SDFs
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Fresnel reflectance calculation
float fresnel(vec3 I, vec3 N, float ior) {
    float cosi = clamp(-1.0, 1.0, dot(I, N));
    float etai = 1.0, etat = ior;
    if (cosi > 0.0) {
        float temp = etai;
        etai = etat;
        etat = temp;
    }
    float sint = etai / etat * sqrt(max(0.0, 1.0 - cosi * cosi));
    if (sint >= 1.0) {
        return 1.0; // Total internal reflection
    }
    float cost = sqrt(max(0.0, 1.0 - sint * sint));
    cosi = abs(cosi);
    float Rs = ((etat * cosi) - (etai * cost)) / ((etat * cosi) + (etai * cost));
    float Rp = ((etai * cosi) - (etat * cost)) / ((etai * cosi) + (etat * cost));
    return (Rs * Rs + Rp * Rp) / 2.0;
}

// Optimized gaussian blur using mipmaps
const int samples = 32;
const int LOD = 1;
const int sLOD = 1 << LOD;
const float sigma = float(samples) * 0.35;

float gaussian(vec2 i) {
    return exp(-0.5 * dot(i /= sigma, i)) / (6.28 * sigma * sigma);
}

// Modified blur function for background sampling
vec3 efficientBlur(vec2 uv, float blurStrength) {
    vec3 O = vec3(0.0);
    float totalWeight = 0.0;
    int s = samples / sLOD;

    for (int i = 0; i < s * s; i++) {
        vec2 d = vec2(i % s, i / s) * float(sLOD) - float(samples) / 2.0;
        vec2 offset = d * blurStrength * 0.0005;
        float weight = gaussian(d);

        // Sample background (image or checker pattern)
        vec3 sampleColor = sampleBackground(uv + offset);

        O += sampleColor * weight;
        totalWeight += weight;
    }

    return O / totalWeight;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // Mouse position (normalized to screen space)
    vec2 mouse = (iMouse.xy - 0.5 * iResolution.xy) / iResolution.y;

    // Fixed superellipse position
    vec2 pos1 = vec2(-0.3, 0.0);

    // Mouse-controlled superellipse position - starts on right side
    vec2 pos2 = iMouse.z > 0.5 ? mouse : vec2(0.3, 0.0);

    // Superellipse parameters
    float radius = 0.2;
    float n = 4.0;

    // Calculate distances to both superellipses
    vec3 dg1 = sdSuperellipse(uv - pos1, radius, n);
    vec3 dg2 = sdSuperellipse(uv - pos2, radius, n);
    float d1 = dg1.x;
    float d2 = dg2.x;

    // Blend the two SDFs together
    float blendRadius = 0.15;
    float d = smin(d1, d2, blendRadius);

    // Calculate drop shadows - no X offset, more blur
    vec2 shadowOffset = vec2(0.0, -0.01); // Only downward shadow
    float shadowBlur = 0.05; // Much blurrier shadow

    // Shadow SDFs (offset shapes)
    float shadow1 = sdSuperellipse(uv - pos1 - shadowOffset, radius, n).x;
    float shadow2 = sdSuperellipse(uv - pos2 - shadowOffset, radius, n).x;
    float shadowSDF = smin(shadow1, shadow2, blendRadius);

    // Create shadow mask
    float shadowMask = 1.0 - smoothstep(0.0, shadowBlur, shadowSDF);
    shadowMask *= 0.1; // Shadow opacity

    // Base background color (image or checker pattern)
    vec3 baseColor = sampleBackground(uv);

    // Apply drop shadow to background
    baseColor = mix(baseColor, vec3(0.0), shadowMask);

    // Apply glass effects inside the shape
    if (d < 0.0) {
        // Calculate blend weights for smooth center interpolation
        float w1 = exp(-d1 * d1 * 8.0);
        float w2 = exp(-d2 * d2 * 8.0);
        float totalWeight = w1 + w2 + 1e-6;

        // Blended center position
        vec2 center = (pos1 * w1 + pos2 * w2) / totalWeight;

        // Distance and direction from blended center
        vec2 offset = uv - center;
        float distFromCenter = length(offset);

        // Distance from edge
        float depthInShape = abs(d);
        float normalizedDepth = clamp(depthInShape / (radius * 0.8), 0.0, 1.0);

        // Exponential distortion
        float edgeFactor = 1.0 - normalizedDepth;
        float exponentialDistortion = exp(edgeFactor * 3.0) - 1.0;

        // Base magnification
        float baseMagnification = 0.75;

        // Lens distortion strength
        float lensStrength = 0.4;
        float distortionAmount = exponentialDistortion * lensStrength;

        // Chromatic aberration
        float baseDistortion = baseMagnification + distortionAmount * distFromCenter;

        float redDistortion = baseDistortion * 0.9;
        float greenDistortion = baseDistortion * 1.0;
        float blueDistortion = baseDistortion * 1.1;

        vec2 redUV = center + offset * redDistortion;
        vec2 greenUV = center + offset * greenDistortion;
        vec2 blueUV = center + offset * blueDistortion;

        // Apply blur and chromatic aberration
        float blurStrength = edgeFactor * 0.0 + 1.5;

        vec3 redBlur = efficientBlur(redUV, blurStrength);
        vec3 greenBlur = efficientBlur(greenUV, blurStrength);
        vec3 blueBlur = efficientBlur(blueUV, blurStrength);

        vec3 refractedColor = vec3(redBlur.r, greenBlur.g, blueBlur.b);

        // Apply glass tint and brightness
        refractedColor *= vec3(0.95, 0.98, 1.0);
        refractedColor += vec3(0.2);

        // Calculate fresnel
        vec2 eps = vec2(0.01, 0.0);
        vec2 gradient = vec2(
            smin(sdSuperellipse(uv + eps.xy - pos1, radius, n).x,
                 sdSuperellipse(uv + eps.xy - pos2, radius, n).x, blendRadius) -
            smin(sdSuperellipse(uv - eps.xy - pos1, radius, n).x,
                 sdSuperellipse(uv - eps.xy - pos2, radius, n).x, blendRadius),
            smin(sdSuperellipse(uv + eps.yx - pos1, radius, n).x,
                 sdSuperellipse(uv + eps.yx - pos2, radius, n).x, blendRadius) -
            smin(sdSuperellipse(uv - eps.yx - pos1, radius, n).x,
                 sdSuperellipse(uv - eps.yx - pos2, radius, n).x, blendRadius)
        );
        vec3 normal = normalize(vec3(gradient, 1.0));
        vec3 viewDir = vec3(0.0, 0.0, -1.0);
        float fresnelAmount = fresnel(viewDir, normal, 1.5);

        // Add fresnel reflection
        vec3 fresnelColor = vec3(1.0);
        vec3 finalColor = mix(refractedColor, fresnelColor, fresnelAmount * 0.3);

        fragColor = vec4(finalColor, 1.0);
    } else {
        // Outside the glass - show background with shadows
        fragColor = vec4(baseColor, 1.0);
    }

    // Add edge line when SDF is near 0 - MORE PROMINENT
    float edgeThickness = 0.008; // Thicker edge
    float edgeMask = smoothstep(edgeThickness, 0.0, abs(d));

    if (edgeMask > 0.0) {
        // Much more prominent diagonal highlights
        vec2 normalizedPos = uv * 1.5; // Adjusted scale for better effect

        // Create stronger diagonal pattern
        float diagonal1 = abs(normalizedPos.x + normalizedPos.y); // Top-left to bottom-right
        float diagonal2 = abs(normalizedPos.x - normalizedPos.y); // Top-right to bottom-left

        // Much more prominent white highlights
        float diagonalFactor = max(
            smoothstep(1.0, 0.1, diagonal1), // Wider white area along main diagonal
            smoothstep(1.0, 0.5, diagonal2)  // Wider white area along anti-diagonal
        );

        // Boost the highlight intensity
        diagonalFactor = pow(diagonalFactor, 1.8); // Makes highlights more prominent

        // Brighter white highlights, darker internal color
        vec3 edgeWhite = vec3(1.2); // Super bright white
        vec3 internalColor = fragColor.rgb * 0.4; // Much darker internal color

        // Mix with stronger contrast
        vec3 edgeColor = mix(internalColor, edgeWhite, diagonalFactor);

        // Blend edge line with existing color - stronger blend
        fragColor.rgb = mix(fragColor.rgb, edgeColor, edgeMask * 1.0);
    }
}
