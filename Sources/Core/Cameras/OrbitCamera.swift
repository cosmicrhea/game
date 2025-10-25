// Default orbit camera values
private let defaultDistance: Float = 0.25
private let defaultSensitivity: Float = 0.3
private let minDistance: Float = 0.1
private let maxDistance: Float = 1.0

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

  // Internal mouse tracking state
  private var lastMouseX: Float = 0
  private var lastMouseY: Float = 0
  private var isFirstMouseEvent: Bool = true
  private var isDragging: Bool = false

  // Momentum/inertia
  private var angularVelocity: (yaw: Float, pitch: Float) = (0, 0)
  private let friction: Float = 0.93  // How quickly momentum decays (lower = more friction)
  private let maxAngularVelocity: Float = 150.0  // Max rotation speed

  // Keyboard controls
  private let keyboardSensitivity: Float = 3.0  // Increased from 1.0
  private let keyboardZoomSpeed: Float = 2.0  // Increased from 0.5

  // Reset animation
  private var isResetting: Bool = false
  private var resetStartTime: Float = 0.0
  private let resetDuration: Float = 1.0
  private var resetStartYaw: Float = 0.0
  private var resetStartPitch: Float = 0.0
  private var resetStartDistance: Float = 0.0
  private let resetTargetYaw: Float = 0.0
  private let resetTargetPitch: Float = 0.0
  private let resetTargetDistance: Float = defaultDistance

  init(
    target: vec3 = vec3(0.0, 0.0, 0.0),
    distance: Float = defaultDistance,
    yaw: Float = -35.6,
    pitch: Float = 14.1
  ) {
    self.target = target
    self.distance = distance
    self.yaw = yaw
    self.pitch = pitch
    self.mouseSensitivity = defaultSensitivity

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

  /// Update the camera with momentum/inertia and reset animation
  func update(deltaTime: Float) {
    // Handle reset animation
    if isResetting {
      resetStartTime += deltaTime
      let progress = min(resetStartTime / resetDuration, 1.0)

      // Use smooth easing for the animation
      let easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress)  // Ease out cubic

      yaw = resetStartYaw + (resetTargetYaw - resetStartYaw) * easedProgress
      pitch = resetStartPitch + (resetTargetPitch - resetStartPitch) * easedProgress
      distance = resetStartDistance + (resetTargetDistance - resetStartDistance) * easedProgress

      updateCameraPosition()

      if progress >= 1.0 {
        isResetting = false
        yaw = resetTargetYaw
        pitch = resetTargetPitch
        distance = resetTargetDistance
        updateCameraPosition()
      }
      return
    }

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
    let yOffset = -yOffset * mouseSensitivity  // Invert Y direction

    // Add to angular velocity for momentum
    angularVelocity.yaw += xOffset * 1.0  // Much more aggressive momentum
    angularVelocity.pitch += yOffset * 1.0

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

  /// Process keyboard state for camera control (polling-based)
  @MainActor func processKeyboardState(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Don't process keyboard input during reset animation
    guard !isResetting else { return }

    // WASD and Arrow keys for rotation
    let rotationSpeed = keyboardSensitivity * deltaTime

    if keyboard.state(of: .w) == .pressed || keyboard.state(of: .up) == .pressed {
      pitch += rotationSpeed
      if pitch > 89.0 { pitch = 89.0 }
      updateCameraPosition()
    }
    if keyboard.state(of: .s) == .pressed || keyboard.state(of: .down) == .pressed {
      pitch -= rotationSpeed
      if pitch < -89.0 { pitch = -89.0 }
      updateCameraPosition()
    }
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      yaw -= rotationSpeed
      updateCameraPosition()
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      yaw += rotationSpeed
      updateCameraPosition()
    }

    // Q and E for zoom
    let zoomSpeed = keyboardZoomSpeed * deltaTime
    if keyboard.state(of: .q) == .pressed {
      distance += zoomSpeed
      if distance > maxDistance { distance = maxDistance }
      updateCameraPosition()
    }
    if keyboard.state(of: .e) == .pressed {
      distance -= zoomSpeed
      if distance < minDistance { distance = minDistance }
      updateCameraPosition()
    }

    // R for reset
    if keyboard.state(of: .r) == .pressed {
      resetToInitialPosition()
    }
  }

  /// Reset camera to initial position with animation
  func resetToInitialPosition() {
    // Don't start a new reset if already resetting
    guard !isResetting else { return }

    // Store current values as starting point
    resetStartYaw = yaw
    resetStartPitch = pitch
    resetStartDistance = distance
    resetStartTime = 0.0
    isResetting = true
  }

  /// Draws debug information in the corner of the screen
  func drawDebugInfo() {
    let debugText = String(
      format: "Orbit: @ %.1f,%.1f,%.1f; yaw:%.1f pitch:%.1f dist:%.2f",
      position.x, position.y, position.z, yaw, pitch, distance
    )

    debugText.draw(
      at: Point(24, Float(Engine.viewportSize.height) - 24),
      style: .itemDescription,
      anchor: .topLeft
    )
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
