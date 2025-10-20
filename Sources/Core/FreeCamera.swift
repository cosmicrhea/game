// Default camera values
private let defaultYaw: Float = -90.0
private let defaultPitch: Float = 0.0
private let defaultSpeed: Float = 2.5
private let defaultSensitivity: Float = 0.1
private let defaultZoom: Float = 1.8

/// A free camera that processes input and calculates the corresponding euler angles,
/// vectors and matrices for use in OpenGL
class FreeCamera {
  // Camera position and orientation vectors
  var position: vec3
  var front: vec3
  var up: vec3
  var right: vec3
  var worldUp: vec3

  // Euler angles
  var yaw: Float
  var pitch: Float

  // Camera settings
  var movementSpeed: Float
  var mouseSensitivity: Float
  var zoom: Float

  // Internal mouse tracking state
  private var lastMouseX: Float = 0
  private var lastMouseY: Float = 0
  private var isFirstMouseEvent: Bool = true

  /// Defines several possible options for camera movement.
  /// Used as abstraction to stay away from window-system specific input methods
  enum Movement {
    case forward
    case backward
    case left
    case right
    case up
    case down
  }

  /// Initialize camera with vector parameters
  init(
    position: vec3 = vec3(0.0, 0.0, 2.0),
    up: vec3 = vec3(0.0, 1.0, 0.0),
    yaw: Float = defaultYaw,
    pitch: Float = defaultPitch
  ) {
    self.position = position
    self.worldUp = up
    self.yaw = yaw
    self.pitch = pitch
    self.movementSpeed = defaultSpeed
    self.mouseSensitivity = defaultSensitivity
    self.zoom = defaultZoom
    self.front = vec3(0.0, 0.0, -1.0)

    // Initialize up and right vectors first
    self.right = vec3(1.0, 0.0, 0.0)
    self.up = vec3(0.0, 1.0, 0.0)

    updateCameraVectors()
  }

  /// Returns the view matrix calculated using Euler Angles and the LookAt Matrix
  func getViewMatrix() -> mat4 {
    return GLMath.lookAt(position, position + front, up)
  }

  /// Processes input received from any keyboard-like input system.
  /// Accepts input parameter in the form of camera defined enum (to abstract it from windowing systems)
  func processMovement(_ direction: Movement, _ deltaTime: Float, _ speedMultiplier: Float = 1) {
    let velocity = movementSpeed * speedMultiplier * deltaTime

    switch direction {
    case .forward:
      position += front * velocity
    case .backward:
      position -= front * velocity
    case .left:
      position -= right * velocity
    case .right:
      position += right * velocity
    case .up:
      position -= up * velocity
    case .down:
      position += up * velocity
    }
  }

  /// Processes GLFW keyboard state.
  @MainActor func processKeyboardState(_ keyboard: Keyboard, _ deltaTime: Float) {
    var speed: Float = 1

    if keyboard.state(of: .leftShift) == .pressed || keyboard.state(of: .rightShift) == .pressed { speed = 3 }
    if keyboard.state(of: .leftAlt) == .pressed || keyboard.state(of: .rightAlt) == .pressed { speed = 1 / 3 }

    if keyboard.state(of: .w) == .pressed { processMovement(.forward, deltaTime, speed) }
    if keyboard.state(of: .s) == .pressed { processMovement(.backward, deltaTime, speed) }
    if keyboard.state(of: .a) == .pressed { processMovement(.left, deltaTime, speed) }
    if keyboard.state(of: .d) == .pressed { processMovement(.right, deltaTime, speed) }
    if keyboard.state(of: .q) == .pressed { processMovement(.up, deltaTime, speed) }
    if keyboard.state(of: .e) == .pressed { processMovement(.down, deltaTime, speed) }
  }

  /// Processes input received from a mouse input system.
  /// Expects the offset value in both the x and y direction.
  func processMouseMovement(
    _ xOffset: Float,
    _ yOffset: Float,
    constrainPitch: Bool = true
  ) {
    let xOffset = xOffset * mouseSensitivity
    let yOffset = yOffset * mouseSensitivity

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

    // Update Front, Right and Up Vectors using the updated Euler angles
    updateCameraVectors()
  }

  /// Processes absolute mouse position and converts it to offsets internally.
  func processMousePosition(_ x: Float, _ y: Float) {
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
    zoom -= yOffset
    if zoom < 1.0 {
      zoom = 1.0
    }
    if zoom > 45.0 {
      zoom = 45.0
    }
  }

  /// Calculates the front vector from the Camera's (updated) Euler Angles
  private func updateCameraVectors() {
    // Calculate the new Front vector
    let frontVector = vec3(
      GLMath.cos(radians(yaw)) * GLMath.cos(radians(pitch)),
      GLMath.sin(radians(pitch)),
      GLMath.sin(radians(yaw)) * GLMath.cos(radians(pitch))
    )

    front = normalize(frontVector)

    // Also re-calculate the Right and Up vector
    // Normalize the vectors, because their length gets closer to 0 the more you look up or down
    // which results in slower movement.
    right = normalize(cross(front, worldUp))
    up = normalize(cross(right, front))
  }
}
