/// A fixed camera that looks at a target point from a fixed position
class FixedCamera {
  var position: vec3
  var target: vec3
  var up: vec3

  init(position: vec3 = vec3(0, 8, 5), target: vec3 = vec3(0, 0, 0), up: vec3 = vec3(0, 1, 0)) {
    self.position = position
    self.target = target
    self.up = up
  }

  /// Get the view matrix for this camera
  func getViewMatrix() -> mat4 {
    return GLMath.lookAt(position, target, up)
  }

  /// Update the camera to follow a target
  func follow(_ newTarget: vec3) {
    target = newTarget
  }

  /// Set the camera position
  func setPosition(_ newPosition: vec3) {
    position = newPosition
  }
}
