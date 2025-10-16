import GLMath

/// Simple directional light for 3D rendering
struct Light {
  var direction: vec3
  var color: vec3
  var intensity: Float

  init(direction: vec3 = vec3(0.0, -1.0, 0.0), color: vec3 = vec3(1.0, 1.0, 1.0), intensity: Float = 1.0) {
    self.direction = normalize(direction)
    self.color = color
    self.intensity = intensity
  }

  /// Create a light pointing down and slightly forward for item inspection
  static func itemInspection() -> Light {
    return Light(
      direction: vec3(0.2, -0.8, 0.3),  // Slightly forward and down
      color: vec3(1.0, 1.0, 0.95),  // Slightly warm white
      intensity: 1.2
    )
  }
}
