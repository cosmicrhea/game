// https://www.shadertoy.com/view/fsdyzB

// Based on shaders from @amine_sebastian and @iq:
//   - https://www.shadertoy.com/view/WtdSDs
//   - https://www.shadertoy.com/view/tltXDl


// TODO: Shadow 'u_colorShadow.a' is unused; Only used 'u_colorShadow.rgb' components


// from https://iquilezles.org/articles/distfunctions
// additional thanks to iq for optimizing conditional block for individual corner radii!
float roundedBoxSDF(vec2 CenterPosition, vec2 Size, vec4 Radius)
{
    Radius.xy = (CenterPosition.x > 0.0) ? Radius.xy : Radius.zw;
    Radius.x  = (CenterPosition.y > 0.0) ? Radius.x  : Radius.y;
    
    vec2 q = abs(CenterPosition)-Size+Radius.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - Radius.x;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // =========================================================================
    // Inputs (uniforms)

    vec2  u_rectSize   = vec2(120.0, 160.0);     // The pixel-space scale of the rectangle.
    vec2  u_rectCenter = vec2(24.0 + 120.0 / 2.0, 24.0 + 160.0 / 2.0); // The pixel-space rectangle center location
    
    float u_edgeSoftness   = 3.0; // How soft the edges should be (in pixels). Higher values could be used to simulate a drop shadow.
    vec4  u_cornerRadiuses = vec4(19.0); // The radiuses of the corners(in pixels): [topRight, bottomRight, topLeft, bottomLeft]
    
    // Border
    float u_borderThickness = 1.0; // The border size (in pixels) 
    float u_borderSoftness  = 0.0; // How soft the (internal) border should be (in pixels)
    
    // Shadow
    float u_shadowSoftness = 20.0;            // The (half) shadow radius (in pixels)
    vec2  u_shadowOffset   = vec2(0.0, 10.0); // The pixel-space shadow offset from rectangle center
    
    // Colors / Background
    // Background comes from the captured screen (iChannel0); this shader is an overlay.
    vec2  uv            = fragCoord.xy / iResolution.xy;
    vec4  baseColor     = texture(iChannel0, uv);
    vec4  u_colorRect   = vec4(0.2, 0.2, 0.2, 1.0); // The color of rectangle
    vec4  u_colorBorder = vec4(0.2, 0.2, 0.2, 1.0); // The color of (internal) border
    vec4  u_colorShadow = vec4(0.2, 0.2, 0.2, 0.1); // The color of shadow
    
    // =========================================================================

    vec2 halfSize = (u_rectSize / 2.0); // Rectangle extents (half of the size)
    
    vec4 radius = u_cornerRadiuses; // Animated corners radiuses
    
    // -------------------------------------------------------------------------
    
    // Calculate distance to edge.   
    float distance = roundedBoxSDF(fragCoord.xy - u_rectCenter, halfSize, radius);
       
    // Smooth the result (free antialiasing).
    float smoothedAlpha = 1.0-smoothstep(0.0, u_edgeSoftness, distance);
    
    // -------------------------------------------------------------------------
    // Border.
    
    float borderAlpha   = 1.0-smoothstep(u_borderThickness - u_borderSoftness, u_borderThickness, abs(distance));
    
    // -------------------------------------------------------------------------
    // Apply a drop shadow effect.
    
    float shadowDistance  = roundedBoxSDF(fragCoord.xy - u_rectCenter + u_shadowOffset, halfSize, radius);
    float shadowAlpha 	  = 1.0-smoothstep(-u_shadowSoftness, u_shadowSoftness, shadowDistance);
    

    // -------------------------------------------------------------------------
    // Debug output
    
        // vec4 debug_sdf = vec4(distance, 0.0, 0.0, 1.0);
    
        // Notice, that instead simple 'alpha' here is used 'min(u_colorRect.a, alpha)' to enable transparency
        // vec4 debug_rect_color   = mix(baseColor, u_colorRect, min(u_colorRect.a, smoothedAlpha));
    
        // Notice, that instead simple 'alpha' here is used 'min(u_colorBorder.a, alpha)' to enable transparency
        // vec4 debug_border_color = mix(baseColor, u_colorBorder, min(u_colorBorder.a, min(borderAlpha, smoothedAlpha)) ); 

    // -------------------------------------------------------------------------
    // Apply colors layer-by-layer: background <- shadow <- rect <- border.
    
    // Blend background with shadow
    vec4 res_shadow_color = mix(baseColor, vec4(u_colorShadow.rgb, shadowAlpha), shadowAlpha);

    // Blend (background+shadow) with rect
    //   Note:
    //     - Used 'min(u_colorRect.a, smoothedAlpha)' instead of 'smoothedAlpha'
    //       to enable rectangle color transparency
    vec4 res_shadow_with_rect_color = 
        mix(
            res_shadow_color,
            u_colorRect,
            min(u_colorRect.a, smoothedAlpha)
        );
        
    // Blend (background+shadow+rect) with border
    //   Note:
    //     - Used 'min(borderAlpha, smoothedAlpha)' instead of 'borderAlpha'
    //       to make border 'internal'
    //     - Used 'min(u_colorBorder.a, alpha)' instead of 'alpha' to enable
    //       border color transparency
    vec4 res_shadow_with_rect_with_border =
        mix(
            res_shadow_with_rect_color,
            u_colorBorder,
            min(u_colorBorder.a, min(borderAlpha, smoothedAlpha))
        );
    
    // -------------------------------------------------------------------------
     
    fragColor = res_shadow_with_rect_with_border;
}
