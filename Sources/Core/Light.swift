/// Enhanced light for 3D rendering with position support
struct Light: @unchecked Sendable {
  var direction: vec3
  var position: vec3
  var color: vec3
  var intensity: Float
  var range: Float
  var type: LightType

  enum LightType {
    case directional
    case point
    case spot
  }

  init(
    direction: vec3 = vec3(0.0, -1.0, 0.0), position: vec3 = vec3(0.0, 0.0, 0.0), color: vec3 = vec3(1.0, 1.0, 1.0),
    intensity: Float = 1.0, range: Float = 100.0, type: LightType = .directional
  ) {
    self.direction = normalize(direction)
    self.position = position
    self.color = color
    self.intensity = intensity
    self.range = range
    self.type = type
  }

  /// Create a light pointing down and slightly forward for item inspection
  static let itemInspection = Light(
    direction: vec3(0.2, -0.8, 0.3),  // Slightly forward and down
    position: vec3(0.0, 2.0, 1.0),  // Position above and in front
    color: vec3(1.0, 0.98, 0.95),  // Slightly warm white
    intensity: 1.2,  // More reasonable intensity to let normal maps show through
    range: 10.0,
    type: .directional
  )

  /// Create a fill light for item inspection to reduce harsh shadows
  static let itemInspectionFill = Light(
    direction: vec3(-0.3, -0.5, -0.2),  // Fill light from the side
    position: vec3(-1.0, 1.0, 0.5),  // Position to the side
    color: vec3(0.8, 0.9, 1.0),  // Cooler fill light
    intensity: 0.4,  // Much more subtle fill light
    range: 8.0,
    type: .point
  )
}
