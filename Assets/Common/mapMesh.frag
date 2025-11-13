#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec3 FragPos;
in vec3 Normal;
in vec4 ClipPos;

// Map rendering uniforms
uniform vec3 fillColor;        // Room/floor fill color
uniform vec3 strokeColor;      // Wall stroke/border color  
uniform vec3 shadowColor;      // Inner shadow color
uniform float shadowSize;      // Inner shadow size in world units
uniform float strokeWidth;     // Stroke/border width in pixels
uniform bool isWireframe;      // Whether we're rendering wireframe for stroke
uniform vec2 viewportSize;     // Viewport size in pixels

// Mesh geometry for distance calculation
uniform vec3 meshBoundsMin;    // Minimum bounds of mesh in world space
uniform vec3 meshBoundsMax;     // Maximum bounds of mesh in world space

// SDF tuning parameters
uniform float sdfGradientScale;      // Scale factor for gradient to pixel conversion
uniform float sdfEpsilon;            // Small value to avoid division by zero
uniform float sdfDistanceOffset;     // Offset to add to SDF distance
uniform float sdfDistanceMultiplier; // Multiplier for SDF distance
uniform float strokeThreshold;       // Additional threshold for stroke
uniform float shadowThreshold;       // Additional threshold for shadow
uniform float shadowStrength;         // Inner shadow strength (0-1)
uniform float shadowFalloff;          // Inner shadow falloff power (higher = softer)
uniform bool debugShowGradient;       // Debug: show gradient instead of stroke

void main() {
  if (isWireframe) {
    // Wireframe mode: render stroke color for borders
    FragColor = vec4(strokeColor, 1.0);
  } else {
    // Calculate distance from fragment to nearest edge of mesh bounding box
    // FragPos is in world space, meshBoundsMin/Max are in world space
    vec3 pos = FragPos;
    
    // Calculate distance to each face of the bounding box (in XZ plane for top-down view)
    float distToLeft = pos.x - meshBoundsMin.x;
    float distToRight = meshBoundsMax.x - pos.x;
    float distToFront = pos.z - meshBoundsMin.z;
    float distToBack = meshBoundsMax.z - pos.z;
    
    // Find minimum distance to any edge (in world units)
    float minDistToEdge = min(min(distToLeft, distToRight), min(distToFront, distToBack));
    
    // Convert world distance to approximate pixel distance
    // Use viewport and camera to estimate pixel size
    // For orthographic camera, we can approximate: 1 world unit ≈ some pixels
    // Use a simple approximation based on viewport size
    float worldToPixelScale = viewportSize.x * 0.01;  // Approximate scale factor
    float pixelDistance = minDistToEdge * worldToPixelScale * sdfGradientScale;
    pixelDistance = (pixelDistance + sdfDistanceOffset) * sdfDistanceMultiplier;
    
    // Calculate stroke: appears when we're within strokeWidth pixels of the edge
    float strokeFactor = 0.0;
    if (strokeWidth > 0.0) {
      // pixelDistance is small near edges, large far from edges
      // We want stroke when pixelDistance < (strokeThreshold + strokeWidth)
      float strokeStart = strokeThreshold;
      float strokeEnd = strokeStart + strokeWidth;
      strokeFactor = 1.0 - smoothstep(strokeStart, strokeEnd, pixelDistance);
    }
    
    // Calculate inner shadow/glow using pixel distance
    float shadowFactor = 0.0;
    if (shadowSize > 0.0) {
      // Shadow extends further from edge than stroke
      // Start shadow right after stroke ends
      float shadowStart = shadowThreshold + strokeWidth;
      float shadowEnd = shadowStart + shadowSize;
      
      // Calculate shadow factor - stronger near edges (smaller pixelDistance)
      shadowFactor = 1.0 - smoothstep(shadowStart, shadowEnd, pixelDistance);
      
      // Apply falloff power for softer effect (higher = more subtle)
      shadowFactor = pow(max(0.0, shadowFactor), shadowFalloff);
    }
    
    // Debug mode: visualize distance
    if (debugShowGradient) {
      // Visualize distance to edge
      float normalizedDist = minDistToEdge / (minDistToEdge + 10.0);
      float normalizedPixelDist = pixelDistance / (pixelDistance + 100.0);
      FragColor = vec4(normalizedDist, normalizedPixelDist, 0.0, 1.0);
      return;
    }
    
    // Combine: fill base, then shadow, then stroke on top
    vec3 finalColor = fillColor;
    
    // Apply inner shadow/glow first (darker near edges, soft falloff)
    if (shadowFactor > 0.0) {
      // Use shadowStrength to control how strong the effect is (more subtle by default)
      finalColor = mix(finalColor, shadowColor, shadowFactor * shadowStrength);
    }
    
    // Apply stroke on top (borders/walls) - strongest effect
    if (strokeFactor > 0.0) {
      finalColor = mix(finalColor, strokeColor, strokeFactor);
    }
    
    FragColor = vec4(finalColor, 1.0);
  }
}

