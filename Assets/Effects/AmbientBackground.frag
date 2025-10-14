#version 330 core
out vec4 FragColor;

in vec2 vUV;             // if you have it (0..1). otherwise compute from gl_FragCoord / uResolution
uniform vec2 uResolution; // framebuffer size in pixels
uniform float iTime;      // seconds

// styling controls
uniform vec3  uTintDark;   // e.g. vec3(0.035, 0.045, 0.055)
uniform vec3  uTintLight;  // e.g. vec3(0.085, 0.10,  0.11)
uniform float uMottle;     // 0..1, base texture strength, e.g. 0.35
uniform float uGrain;      // 0..1, film grain amount, e.g. 0.08
uniform float uVignette;   // 0..1, vignette strength, e.g. 0.35
uniform float uDust;       // 0..1, tiny bright specks, e.g. 0.06

// ---------- noise helpers ----------
float hash21(vec2 p){
    p = fract(p*vec2(123.34, 345.45));
    p += dot(p, p+34.345);
    return fract(p.x*p.y);
}
float n2(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f*f*(3.0-2.0*f);
    float a = hash21(i+vec2(0,0));
    float b = hash21(i+vec2(1,0));
    float c = hash21(i+vec2(0,1));
    float d = hash21(i+vec2(1,1));
    return mix(mix(a,b,u.x), mix(c,d,u.x), u.y);
}
float fbm(vec2 p){
    float a = 0.0, amp = 0.5;
    for(int i=0;i<5;i++){
        a += amp * n2(p);
        p = p*2.02 + 13.37;
        amp *= 0.5;
    }
    return a;
}

void main()
{
    // uv from fragment coord in case vUV isn't provided
    vec2 uv = (gl_FragCoord.xy) / uResolution;

    // slight aspect-corrected mapping for nicer texture scale
    vec2 puv = uv;
    puv.x *= uResolution.x / max(uResolution.y, 1.0);

    // ---------- base diagonal gradient ----------
    // top-left a bit brighter, bottom-right a bit darker
    float diag = dot(normalize(vec2(-1.0, 1.0)), uv - 0.5) * 0.8 + 0.5;
    diag = clamp(diag, 0.0, 1.0);
    vec3 base = mix(uTintDark, uTintLight, diag);

    // ---------- soft mottled paper-like texture ----------
    // two fbm layers with slightly different scales to avoid tiling vibes
    float m1 = fbm(puv * 3.2);
    float m2 = fbm((puv + 7.3) * 6.0);
    float mottle = mix(m1, m2, 0.5);
    // center-preserving curve so it never gets too blotchy
    mottle = (mottle - 0.5) * 0.6;
    base *= (1.0 - uMottle*0.35) + uMottle*0.35 * (1.0 + mottle);

    // ---------- ultra subtle film grain ----------
    // animated high freq hash, per-pixel per-frame
    float grain = hash21(gl_FragCoord.xy + floor(iTime*24.0));
    grain = (grain - 0.5); // centered
    base += uGrain * 0.06 * grain;

    // ---------- rare tiny dust specks (barely visible) ----------
    // thresholded noise adds occasional bright micro specks
    float dustN = fbm(puv*18.0 + 11.0);
    float speck = smoothstep(0.995, 1.0, dustN);  // super sparse
    base += uDust * 0.15 * speck;

    // ---------- gentle vignette ----------
    vec2 c = uv - 0.5;
    float r = dot(c, c); // radial
    float vig = smoothstep(0.65, 0.9, r);
    base *= 1.0 - uVignette * 0.25 * vig;

    // clamp and output
    base = clamp(base, 0.0, 1.0);
    FragColor = vec4(base, 1.0);
}
