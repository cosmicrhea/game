// Default inspection camera values
private let defaultDistance: Float = 0.3  // Closer by default for better inspection
private let defaultSensitivity: Float = 0.3
private let minDistance: Float = 0.1  // Can get closer
private let maxDistance: Float = 0.6  // Don't need to go as far

/// A camera designed for inspecting 3D objects by rotating the model instead of the camera.
/// This keeps lighting consistent while allowing you to see all sides of the object.
/// Note: Unlike other cameras, this one provides a model matrix for rotating the object.
class ItemInspectionCamera {
  // Fixed camera position - we don't move the camera, we rotate the model.
  var position: vec3

  // Target point (where the object is)
  var target: vec3

  // Model rotation angles (this is what we change, not camera angles)
  var modelYaw: Float
  var modelPitch: Float

  // Distance from camera to object (for zoom)
  var distance: Float

  // Camera settings
  var mouseSensitivity: Float

  // Internal mouse tracking state
  private var lastMouseX: Float = 0
  private var lastMouseY: Float = 0
  private var isFirstMouseEvent: Bool = true
  private var isDragging: Bool = false

  // Pan state
  private var isPanning: Bool = false
  private var panOffset: vec3 = vec3(0, 0, 0)

  // Momentum/inertia for smooth rotation
  private var angularVelocity: (yaw: Float, pitch: Float) = (0, 0)
  private let friction: Float = 0.93
  private let maxAngularVelocity: Float = 150.0

  // Momentum/inertia for smooth zoom
  private var zoomVelocity: Float = 0.0
  private let zoomFriction: Float = 0.88
  private let maxZoomVelocity: Float = 2.0

  // Momentum/inertia for smooth panning
  private var panVelocity: vec3 = vec3(0, 0, 0)
  private let panFriction: Float = 0.90
  private let maxPanVelocity: Float = 5.0

  // Keyboard controls
  private let keyboardSensitivity: Float = 100.0
  private let keyboardZoomSpeed: Float = 2.0

  // Reset animation
  private var isResetting: Bool = false
  private var resetStartTime: Float = 0.0
  private let resetDuration: Float = 1.0
  private var resetStartYaw: Float = 0.0
  private var resetStartPitch: Float = 0.0
  private var resetStartDistance: Float = 0.0
  private var resetStartPanOffset: vec3 = vec3(0, 0, 0)
  private let resetTargetYaw: Float = 0.0
  private let resetTargetPitch: Float = 0.0
  private let resetTargetDistance: Float = defaultDistance
  private let initialTarget: vec3

  init(
    target: vec3 = vec3(0.0, 0.0, 0.0),  // Object position
    distance: Float = defaultDistance,
    modelYaw: Float = 0.0,  // Start with model facing camera
    modelPitch: Float = 0.0  // Start with model level
  ) {
    self.target = target
    self.distance = distance
    self.modelYaw = modelYaw
    self.modelPitch = modelPitch
    self.mouseSensitivity = defaultSensitivity
    self.initialTarget = target

    // Calculate camera position based on distance
    self.position = target + vec3(0.0, 0.0, distance)
  }

  /// Returns the view matrix (fixed camera looking at target)
  func getViewMatrix() -> mat4 {
    return GLMath.lookAt(position, target, vec3(0.0, 1.0, 0.0))
  }

  /// Returns the model transformation matrix (this is what rotates the object)
  func getModelMatrix() -> mat4 {
    // Only rotate the model around Y-axis (yaw) - like spinning a turntable
    // The pitch is handled by moving the camera up/down instead
    return GLMath.rotate(mat4(1), radians(modelYaw), vec3(0, 1, 0))
  }

  /// Update the camera with momentum/inertia and reset animation
  func update(deltaTime: Float) {
    // Handle reset animation
    if isResetting {
      resetStartTime += deltaTime
      let progress = min(resetStartTime / resetDuration, 1.0)

      // Use smooth easing for the animation
      let easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress)

      modelYaw = resetStartYaw + (resetTargetYaw - resetStartYaw) * easedProgress
      modelPitch = resetStartPitch + (resetTargetPitch - resetStartPitch) * easedProgress
      distance = resetStartDistance + (resetTargetDistance - resetStartDistance) * easedProgress

      // Animate pan offset back to zero and target back to initial position
      let targetPanOffset = vec3(0, 0, 0)
      panOffset = resetStartPanOffset + (targetPanOffset - resetStartPanOffset) * easedProgress
      target = initialTarget + panOffset

      if progress >= 1.0 {
        isResetting = false
        modelYaw = resetTargetYaw
        modelPitch = resetTargetPitch
        distance = resetTargetDistance
        panOffset = vec3(0, 0, 0)
        target = initialTarget
      }
      return
    }

    // Apply momentum if not dragging
    if !isDragging {
      // Apply angular velocity to model rotation (yaw only)
      modelYaw += angularVelocity.yaw * deltaTime

      // Apply angular velocity to camera pitch
      modelPitch += angularVelocity.pitch * deltaTime

      // Update camera position when pitch changes
      updateCameraPosition()

      // Apply friction to slow down momentum
      angularVelocity.yaw *= friction
      angularVelocity.pitch *= friction
    }

    // Apply zoom momentum
    if abs(zoomVelocity) > 0.01 {
      distance -= zoomVelocity * deltaTime

      // Clamp distance to bounds
      if distance < minDistance {
        distance = minDistance
        zoomVelocity = 0.0  // Stop momentum when hitting bounds
      }
      if distance > maxDistance {
        distance = maxDistance
        zoomVelocity = 0.0  // Stop momentum when hitting bounds
      }

      // Update camera position
      updateCameraPosition()

      // Apply friction to slow down zoom momentum
      zoomVelocity *= zoomFriction
    }

    // Apply pan momentum
    if length(panVelocity) > 0.01 {
      let panDelta = panVelocity * deltaTime
      target += panDelta
      panOffset += panDelta

      // Update camera position
      updateCameraPosition()

      // Apply friction to slow down pan momentum
      panVelocity *= panFriction
    }
  }

  /// Processes input received from a mouse input system.
  func processMouseMovement(
    _ xOffset: Float,
    _ yOffset: Float,
    constrainPitch: Bool = true,
    isAltPressed: Bool = false
  ) {
    // Only process movement if we're dragging
    guard isDragging else { return }

    let xOffset = xOffset * mouseSensitivity
    let yOffset = -yOffset * mouseSensitivity  // Invert Y direction

    if isAltPressed {
      // Pan mode: move the target point
      isPanning = true

      // Convert mouse movement to world space pan
      // X movement pans left/right, Y movement pans up/down
      let panSensitivity: Float = 0.005
      let rightVector = cross(vec3(0, 1, 0), normalize(target - position))
      let upVector = vec3(0, 1, 0)

      let panDelta = rightVector * xOffset * panSensitivity + upVector * yOffset * panSensitivity
      panVelocity += panDelta

      // Clamp pan velocity
      let panSpeed = length(panVelocity)
      if panSpeed > maxPanVelocity {
        panVelocity = normalize(panVelocity) * maxPanVelocity
      }

      // Apply pan immediately for responsive feel
      panOffset += panDelta
      target += panDelta
    } else {
      // Rotation mode: rotate the model
      isPanning = false

      // X-axis: Rotate the model (yaw)
      angularVelocity.yaw += xOffset * 1.0
      angularVelocity.yaw = max(-maxAngularVelocity, min(maxAngularVelocity, angularVelocity.yaw))
      modelYaw += xOffset

      // Y-axis: Move the camera up/down (pitch)
      angularVelocity.pitch += yOffset * 1.0
      angularVelocity.pitch = max(-maxAngularVelocity, min(maxAngularVelocity, angularVelocity.pitch))
      modelPitch += yOffset

      // Constrain pitch to prevent flipping
      if constrainPitch {
        if modelPitch > 89.0 {
          modelPitch = 89.0
        }
        if modelPitch < -89.0 {
          modelPitch = -89.0
        }
      }

      // Update camera position based on pitch
      updateCameraPosition()
    }
  }

  /// Processes absolute mouse position and converts it to offsets internally.
  func processMousePosition(_ x: Float, _ y: Float, isAltPressed: Bool = false) {
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

    processMouseMovement(xOffset, yOffset, isAltPressed: isAltPressed)
  }

  /// Processes input received from a mouse scroll-wheel event.
  func processMouseScroll(_ yOffset: Float) {
    // Add to zoom velocity for momentum
    let scrollSensitivity: Float = 0.8
    zoomVelocity += yOffset * scrollSensitivity

    // Clamp zoom velocity
    zoomVelocity = max(-maxZoomVelocity, min(maxZoomVelocity, zoomVelocity))
  }

  /// Start dragging (call when left mouse button is pressed)
  func startDragging() {
    isDragging = true
    isFirstMouseEvent = true
  }

  /// Stop dragging (call when left mouse button is released)
  func stopDragging() {
    isDragging = false
  }

  /// Process keyboard state for camera control (polling-based)
  @MainActor func processKeyboardState(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Don't process keyboard input during reset animation
    guard !isResetting else { return }

    // WASD and Arrow keys for model rotation
    let rotationSpeed = keyboardSensitivity * deltaTime

    if keyboard.state(of: .w) == .pressed || keyboard.state(of: .up) == .pressed {
      modelPitch += rotationSpeed
      if modelPitch > 89.0 { modelPitch = 89.0 }
      updateCameraPosition()  // Update camera when pitch changes
    }
    if keyboard.state(of: .s) == .pressed || keyboard.state(of: .down) == .pressed {
      modelPitch -= rotationSpeed
      if modelPitch < -89.0 { modelPitch = -89.0 }
      updateCameraPosition()  // Update camera when pitch changes
    }
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      modelYaw -= rotationSpeed
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      modelYaw += rotationSpeed
    }

    // Q and E for zoom (using momentum system)
    let zoomSpeed = keyboardZoomSpeed * deltaTime
    if keyboard.state(of: .q) == .pressed {
      zoomVelocity += zoomSpeed
    }
    if keyboard.state(of: .e) == .pressed {
      zoomVelocity -= zoomSpeed
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

    // Clear momentum
    angularVelocity = (0, 0)
    zoomVelocity = 0.0
    panVelocity = vec3(0, 0, 0)

    // Store current values as starting point
    resetStartYaw = modelYaw
    resetStartPitch = modelPitch
    resetStartDistance = distance
    resetStartPanOffset = panOffset
    resetStartTime = 0.0
    isResetting = true
  }

  /// Draws debug information in the corner of the screen
  func drawDebugInfo() {
    let debugText = String(
      format: "Inspect: @ %.1f,%.1f,%.1f; modelYaw:%.1f modelPitch:%.1f dist:%.2f pan:%.2f,%.2f,%.2f",
      position.x, position.y, position.z, modelYaw, modelPitch, distance, panOffset.x, panOffset.y, panOffset.z
    )

    let determinationStyle = TextStyle(fontName: "Determination", fontSize: 32, color: .white)

    debugText.draw(
      at: Point(24, Float(Engine.viewportSize.height) - 24),
      style: determinationStyle,
      anchor: .topLeft
    )
  }

  /// Updates the camera position based on target, distance, and pitch
  private func updateCameraPosition() {
    // Calculate camera position based on distance and pitch
    // This is similar to OrbitCamera but we keep the model at the center
    position =
      target
      + vec3(
        0.0,  // Keep X at 0 for simple rotation
        distance * GLMath.sin(radians(modelPitch)),  // Y based on pitch
        distance * GLMath.cos(radians(modelPitch))  // Z based on pitch
      )
  }
}
