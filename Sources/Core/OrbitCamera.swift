import GL
import GLFW
import GLMath

// Default orbit camera values
private let defaultDistance: Float = 3.0
private let defaultSensitivity: Float = 0.1
private let defaultZoom: Float = 1.8
private let minDistance: Float = 0.5
private let maxDistance: Float = 10.0

/// An orbit camera that rotates around a target point, perfect for inspecting objects
class OrbitCamera {
  // Target point that the camera orbits around
  var target: vec3

  // Camera position (calculated from target + distance + angles)
  var position: vec3

  // Camera orientation
  var yaw: Float
  var pitch: Float

  // Distance from target
  var distance: Float

  // Camera settings
  var mouseSensitivity: Float
  var zoom: Float

  // Internal mouse tracking state
  private var lastMouseX: Float = 0
  private var lastMouseY: Float = 0
  private var isFirstMouseEvent: Bool = true
  private var isDragging: Bool = false

  // Momentum/inertia
  private var angularVelocity: (yaw: Float, pitch: Float) = (0, 0)
  private let friction: Float = 0.95  // How quickly momentum decays
  private let maxAngularVelocity: Float = 10.0  // Max rotation speed

  init(
    target: vec3 = vec3(0.0, 0.0, 0.0),
    distance: Float = defaultDistance,
    yaw: Float = 0.0,
    pitch: Float = 0.0
  ) {
    self.target = target
    self.distance = distance
    self.yaw = yaw
    self.pitch = pitch
    self.mouseSensitivity = defaultSensitivity
    self.zoom = defaultZoom

    // Calculate initial position
    self.position =
      target
      + vec3(
        distance * GLMath.cos(radians(yaw)) * GLMath.cos(radians(pitch)),
        distance * GLMath.sin(radians(pitch)),
        distance * GLMath.sin(radians(yaw)) * GLMath.cos(radians(pitch))
      )
  }

  /// Returns the view matrix calculated using the orbit camera
  func getViewMatrix() -> mat4 {
    return GLMath.lookAt(position, target, vec3(0.0, 1.0, 0.0))
  }

  /// Update the camera with momentum/inertia
  func update(deltaTime: Float) {
    // Apply momentum if not dragging
    if !isDragging {
      // Apply angular velocity
      yaw += angularVelocity.yaw * deltaTime
      pitch += angularVelocity.pitch * deltaTime

      // Apply friction to slow down momentum
      angularVelocity.yaw *= friction
      angularVelocity.pitch *= friction

      // Update camera position
      updateCameraPosition()
    }
  }

  /// Processes input received from a mouse input system.
  /// Expects the offset value in both the x and y direction.
  func processMouseMovement(
    _ xOffset: Float,
    _ yOffset: Float,
    constrainPitch: Bool = true
  ) {
    // Only process movement if we're dragging
    guard isDragging else { return }

    let xOffset = xOffset * mouseSensitivity
    let yOffset = yOffset * mouseSensitivity

    // Add to angular velocity for momentum
    angularVelocity.yaw += xOffset * 0.1  // Scale down for momentum
    angularVelocity.pitch += yOffset * 0.1

    // Clamp angular velocity
    angularVelocity.yaw = max(-maxAngularVelocity, min(maxAngularVelocity, angularVelocity.yaw))
    angularVelocity.pitch = max(-maxAngularVelocity, min(maxAngularVelocity, angularVelocity.pitch))

    yaw += xOffset
    pitch += yOffset

    // Make sure that when pitch is out of bounds, screen doesn't get flipped
    if constrainPitch {
      if pitch > 89.0 {
        pitch = 89.0
      }
      if pitch < -89.0 {
        pitch = -89.0
      }
    }

    // Update camera position based on new angles
    updateCameraPosition()
  }

  /// Processes absolute mouse position and converts it to offsets internally.
  func processMousePosition(_ x: Float, _ y: Float) {
    // Only process mouse movement if we're actually dragging
    guard isDragging else { return }

    if isFirstMouseEvent {
      lastMouseX = x
      lastMouseY = y
      isFirstMouseEvent = false
      return
    }

    let xOffset = x - lastMouseX
    let yOffset = lastMouseY - y  // invert Y so up is positive

    lastMouseX = x
    lastMouseY = y

    processMouseMovement(xOffset, yOffset)
  }

  /// Processes input received from a mouse scroll-wheel event.
  /// Only requires input on the vertical wheel-axis
  func processMouseScroll(_ yOffset: Float) {
    distance -= yOffset * 0.3  // Make zoom more responsive
    if distance < minDistance {
      distance = minDistance
    }
    if distance > maxDistance {
      distance = maxDistance
    }

    // Update camera position with new distance
    updateCameraPosition()
  }

  /// Start dragging (call when left mouse button is pressed)
  func startDragging() {
    isDragging = true
    isFirstMouseEvent = true  // Reset first mouse event when starting drag
  }

  /// Stop dragging (call when left mouse button is released)
  func stopDragging() {
    isDragging = false
  }

  /// Updates the camera position based on target, distance, and angles
  private func updateCameraPosition() {
    position =
      target
      + vec3(
        distance * GLMath.cos(radians(yaw)) * GLMath.cos(radians(pitch)),
        distance * GLMath.sin(radians(pitch)),
        distance * GLMath.sin(radians(yaw)) * GLMath.cos(radians(pitch))
      )
  }
}
