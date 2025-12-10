import CJolt
import Foundation
import Jolt

/// Wraps Jolt's CharacterVirtual and handles player movement, footstep tracking, and character controller management
@MainActor
public final class PlayerController {
  // MARK: - State

  var position: vec3 = vec3(0, 0, 0)
  var rotation: Float = 0.0

  private var spawnPosition: vec3 = vec3(0, 0, 0)
  private var spawnRotation: Float = 0.0

  private var moveSpeed: Float = 3.0
  private var rotationSpeed: Float = 4.0  // radians per second

  // Footstep tracking
  private var footstepAccumulatedDistance: Float = 0.0
  private var previousPlayerPosition: vec3 = vec3(0, 0, 0)
  private let footstepDistanceWalk: Float = 1.2  // Distance between footsteps when walking
  private let footstepDistanceRun: Float = 1.5  // Distance between footsteps when running (faster rate)

  // MARK: - Sensor Box Dimensions

  /// Width of the action detection sensor box.
  private let sensorWidth: Float = 0.6

  /// Height of the action detection sensor box.
  private let sensorHeight: Float = 1.75

  /// Depth of the action detection sensor box.
  /// This is how far forward the sensor extends from the player.
  private let sensorDepth: Float = 0.4

  /// Distance from player position to the front edge of the sensor box.
  private let sensorDistance: Float = 0

  // MARK: - Character Controller

  private var characterController: CharacterVirtual?

  // Sensor body in front of capsule for detecting action triggers
  private var capsuleSensorBodyID: BodyID?

  // MARK: - References

  private weak var physicsWorld: PhysicsWorld?

  // MARK: - Initialization

  public init(physicsWorld: PhysicsWorld) {
    self.physicsWorld = physicsWorld
  }

  // MARK: - Character Controller Management

  /// Create character controller at specified position and rotation
  public func create(at position: vec3, rotation: Float) {
    guard let physicsWorld = physicsWorld else {
      logger.error("⚠️ Cannot create character controller: no physics world")
      return
    }

    // If character controller already exists, remove it first
    if characterController != nil {
      // Remove old sensor body if it exists
      if let sensorBodyID = capsuleSensorBodyID {
        // Unregister from contact listener before removing
        physicsWorld.unregisterSensorBody(sensorBodyID)
        let bodyInterface = physicsWorld.bodyInterface()
        bodyInterface.removeAndDestroyBody(sensorBodyID)
        logger.trace("✅ Removed old capsule sensor body ID: \(sensorBodyID)")
      }
      characterController = nil
      capsuleSensorBodyID = nil
    }

    // Create capsule shape for character (radius ~0.4, halfHeight ~0.8)
    let capsuleRadius: Float = 0.4
    let capsuleHalfHeight: Float = 0.8
    let capsuleShape = CapsuleShape(halfHeight: capsuleHalfHeight, radius: capsuleRadius)

    // Create supporting volume (plane at bottom of capsule for ground detection)
    let supportingPlane = Plane(normal: Vec3(x: 0, y: 1, z: 0), distance: -capsuleRadius)

    // Create character settings
    let characterSettings = CharacterVirtualSettings(
      up: Vec3(x: 0, y: 1, z: 0),
      supportingVolume: supportingPlane,
      shape: capsuleShape
    )

    // Convert rotation to quaternion
    let rotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))

    // Create character controller
    characterController = CharacterVirtual(
      settings: characterSettings,
      position: RVec3(x: position.x, y: position.y, z: position.z),
      rotation: rotationQuat,
      in: physicsWorld.getPhysicsSystem()
    )

    // Set mass and strength
    characterController?.mass = 70.0  // kg
    characterController?.maxStrength = 500.0  // N

    // Initialize footstep tracking position
    previousPlayerPosition = position

    // Create action sensor box in front of player
    //createActionSensorBox(at: position, rotation: rotation)

    logger.trace("✅ Created character controller at position (\(position.x), \(position.y), \(position.z))")
  }

  // /// Create action sensor box in front of player (box shape, not capsule)
  // private func createActionSensorBox(at position: vec3, rotation: Float) {
  //   guard let physicsWorld = physicsWorld else { return }
  //   let bodyInterface = physicsWorld.bodyInterface()

  //   // Create a box sensor in front of the capsule
  //   // Box extends forward from player position
  //   // Dimensions are defined as class constants above

  //   let boxHalfExtents = Vec3(x: sensorWidth * 0.5, y: sensorHeight * 0.5, z: sensorDepth * 0.5)
  //   let sensorShape = BoxShape(halfExtent: boxHalfExtents)

  //   // Position sensor in front of capsule (using forward direction)
  //   let forwardX = GLMath.sin(rotation)
  //   let forwardZ = GLMath.cos(rotation)
  //   // Center the box at sensorDistance + depth/2 in front of player
  //   let sensorOffset = vec3(
  //     forwardX * (sensorDistance + sensorDepth * 0.5), 0, forwardZ * (sensorDistance + sensorDepth * 0.5))
  //   let sensorPosition = position + sensorOffset

  //   // Create rotation quaternion for the box (aligned with player rotation)
  //   let rotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))

  //   // Create body settings - make it a kinematic sensor so it moves with the capsule
  //   let bodySettings = BodyCreationSettings(
  //     shape: sensorShape,
  //     position: RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z),
  //     rotation: rotationQuat,
  //     motionType: .kinematic,
  //     objectLayer: 2  // Same layer as character
  //   )
  //   bodySettings.isSensor = true  // Make it a sensor

  //   // Create and add sensor body
  //   let sensorBodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
  //   if sensorBodyID != 0 {
  //     capsuleSensorBodyID = sensorBodyID
  //     // Register sensor body for contact tracking
  //     physicsWorld.registerSensorBody(sensorBodyID)
  //     // Register body name for debugging
  //     physicsWorld.registerBodyName(sensorBodyID, name: "Player Action Sensor Box")
  //     logger.trace("✅ Created action sensor box body ID: \(sensorBodyID)")
  //   } else {
  //     logger.error("❌ Failed to create action sensor box")
  //   }
  // }

  /// Get character controller (for InteractionSystem to check contacts)
  public func getCharacterController() -> CharacterVirtual? {
    return characterController
  }

  /// Get sensor body ID (for InteractionSystem)
  public func getSensorBodyID() -> BodyID? {
    return capsuleSensorBodyID
  }

  // MARK: - Position & Rotation

  /// Set spawn position and rotation
  public func setSpawn(position: vec3, rotation: Float) {
    spawnPosition = position
    spawnRotation = rotation
  }

  /// Set position and rotation (for positioning at entry)
  public func setPosition(_ newPosition: vec3, rotation newRotation: Float) {
    position = newPosition
    rotation = newRotation
    previousPlayerPosition = newPosition  // Reset footstep tracking
    footstepAccumulatedDistance = 0.0  // Reset footstep accumulator

    // Update character controller if it exists
    if let characterController {
      characterController.position = RVec3(x: newPosition.x, y: newPosition.y, z: newPosition.z)
      let rotationQuat = Quat(x: 0, y: sin(newRotation / 2), z: 0, w: cos(newRotation / 2))
      characterController.rotation = rotationQuat
      characterController.linearVelocity = Vec3(x: 0, y: 0, z: 0)  // Stop all movement
    }
  }

  /// Reset player to spawn position
  public func resetToSpawn() {
    position = spawnPosition
    rotation = spawnRotation
    previousPlayerPosition = spawnPosition  // Reset footstep tracking
    footstepAccumulatedDistance = 0.0  // Reset footstep accumulator

    // Also reset character controller if it exists
    if let characterController {
      characterController.position = RVec3(x: spawnPosition.x, y: spawnPosition.y, z: spawnPosition.z)
      let rotationQuat = Quat(x: 0, y: sin(spawnRotation / 2), z: 0, w: cos(spawnRotation / 2))
      characterController.rotation = rotationQuat
      characterController.linearVelocity = Vec3(x: 0, y: 0, z: 0)  // Stop all movement
    }
  }

  /// Check if character is supported (on ground)
  public var isSupported: Bool {
    return characterController?.isSupported ?? false
  }

  // MARK: - Movement

  /// Update movement based on keyboard input
  public func update(
    keyboard: Keyboard,
    deltaTime: Float,
    physicsWorld: PhysicsWorld,
    isAiming: Bool
  ) {
    guard let characterController = characterController else { return }
    guard physicsWorld.isReady else { return }

    // Tank controls: A/D rotate, W/S move forward/backward
    let rotationDelta = rotationSpeed * deltaTime

    // Always allow rotation, even while aiming
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      rotation += rotationDelta
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      rotation -= rotationDelta
    }

    // Don't allow forward/backward movement while aiming
    if isAiming { return }

    // Calculate forward direction from rotation
    let forwardX = GLMath.sin(rotation)
    let forwardZ = GLMath.cos(rotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Check for speed boost (Shift key)
    let speedMultiplier: Float
    if keyboard.state(of: .leftShift) == .pressed || keyboard.state(of: .rightShift) == .pressed {
      speedMultiplier = 2.5  // 2.5x speed when holding Shift
    } else {
      speedMultiplier = 1.0
    }
    let currentMoveSpeed = moveSpeed * speedMultiplier

    // Calculate desired horizontal velocity from input
    var desiredVelocity = Vec3(x: 0, y: 0, z: 0)

    if keyboard.state(of: .w) == .pressed || keyboard.state(of: .up) == .pressed {
      desiredVelocity = Vec3(x: forward.x * currentMoveSpeed, y: 0, z: forward.z * currentMoveSpeed)
    } else if keyboard.state(of: .s) == .pressed || keyboard.state(of: .down) == .pressed {
      desiredVelocity = Vec3(x: -forward.x * currentMoveSpeed, y: 0, z: -forward.z * currentMoveSpeed)
    }

    // Get current velocity and preserve Y component (gravity)
    var currentVelocity = characterController.linearVelocity
    let currentYVelocity = currentVelocity.y

    // Set horizontal velocity directly (no smoothing - character controller handles it)
    currentVelocity.x = desiredVelocity.x
    currentVelocity.z = desiredVelocity.z
    // Apply gravity if not on ground
    if !characterController.isSupported {
      currentVelocity.y = currentYVelocity + physicsWorld.getGravity().y * deltaTime
    } else {
      currentVelocity.y = 0  // On ground, no vertical velocity
    }

    characterController.linearVelocity = currentVelocity

    // Update character rotation
    let rotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))
    characterController.rotation = rotationQuat

    // // Update sensor body position BEFORE physics update so contacts are detected correctly
    // // Use character controller's current position (which will be updated this frame)
    // if let sensorBodyID = capsuleSensorBodyID {
    //   let bodyInterface = physicsWorld.bodyInterface()

    //   // Get current character controller position
    //   let currentCharPos = characterController.position
    //   let currentPos = vec3(currentCharPos.x, currentCharPos.y, currentCharPos.z)

    //   // Calculate position in front of capsule based on current rotation
    //   // Sensor should stay at fixed distance in front, not move forward with player
    //   let forwardX = GLMath.sin(rotation)
    //   let forwardZ = GLMath.cos(rotation)
    //   // Center the box at sensorDistance + depth/2 in front of player
    //   let sensorOffset = vec3(
    //     forwardX * (sensorDistance + sensorDepth * 0.5), 0, forwardZ * (sensorDistance + sensorDepth * 0.5))
    //   let sensorPosition = currentPos + sensorOffset

    //   // Update sensor position and rotation using Body wrapper
    //   var sensorBody = bodyInterface.body(sensorBodyID, in: physicsWorld.getPhysicsSystem())
    //   sensorBody.position = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)
    //   let sensorRotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))
    //   sensorBody.rotation = sensorRotationQuat
    // }

    // Update physics system FIRST (jobSystem is required)
    // This internally waits for all jobs to complete, so it's synchronous
    // This ensures the physics world is in a consistent state before character controller updates
    physicsWorld.update(deltaTime: deltaTime, collisionSteps: 1)

    // Update character controller (this does the physics movement)
    let characterLayer: ObjectLayer = 2  // Dynamic layer
    characterController.update(deltaTime: deltaTime, layer: characterLayer, in: physicsWorld.getPhysicsSystem())

    // Read position immediately after character controller update
    // This gives us the position from the character controller's internal state
    let characterPos = characterController.position
    let newPosition = vec3(characterPos.x, characterPos.y, characterPos.z)

    // Calculate horizontal distance moved (ignore vertical movement)
    let horizontalDelta = vec3(
      newPosition.x - previousPlayerPosition.x,
      0,
      newPosition.z - previousPlayerPosition.z
    )
    let distanceMoved = length(horizontalDelta)

    // Check if player is moving (has input)
    let isMoving =
      keyboard.state(of: .w) == .pressed || keyboard.state(of: .s) == .pressed
      || keyboard.state(of: .up) == .pressed || keyboard.state(of: .down) == .pressed

    // Only accumulate distance and play footsteps if moving and on ground
    if isMoving && characterController.isSupported {
      footstepAccumulatedDistance += distanceMoved

      // Determine footstep rate based on running vs walking
      let footstepThreshold = speedMultiplier > 1.0 ? footstepDistanceRun : footstepDistanceWalk

      // Play footstep when threshold is reached
      if footstepAccumulatedDistance >= footstepThreshold {
        UISound.footstep()
        footstepAccumulatedDistance = 0.0  // Reset accumulator
      }
    } else {
      // Not moving or not on ground - reset accumulator
      footstepAccumulatedDistance = 0.0
    }

    // Update previous position for next frame
    previousPlayerPosition = newPosition
    position = newPosition

    // Note: Sensor body position is now updated BEFORE physics update (see above)
    // This ensures contacts are detected correctly during the physics step
  }

  /// Clear character controller (when scene changes)
  public func clear() {
    // Remove sensor body from physics world before clearing
    if let sensorBodyID = capsuleSensorBodyID, let physicsWorld = physicsWorld {
      // Unregister from contact listener before removing
      physicsWorld.unregisterSensorBody(sensorBodyID)
      let bodyInterface = physicsWorld.bodyInterface()
      bodyInterface.removeAndDestroyBody(sensorBodyID)
      logger.trace("✅ Removed action sensor box body ID: \(sensorBodyID)")
    }

    characterController = nil
    capsuleSensorBodyID = nil
  }

  // MARK: - Sensor Box Query Support

  /// Get sensor box transform for collision queries
  public func getSensorBoxTransform() -> (position: vec3, rotation: Quat, halfExtents: Vec3) {
    // Get current character controller position
    let currentCharPos = characterController?.position ?? RVec3(x: position.x, y: position.y, z: position.z)
    let currentPos = vec3(currentCharPos.x, currentCharPos.y, currentCharPos.z)

    // Calculate position in front of capsule based on current rotation
    let forwardX = GLMath.sin(rotation)
    let forwardZ = GLMath.cos(rotation)
    // Center the box at sensorDistance + depth/2 in front of player
    // Align sensor box bottom with capsule bottom
    // Capsule: radius 0.4, halfHeight 0.8, so bottom is at position.y - 1.2
    // Sensor box: height 1.75, halfHeight 0.875
    // To align bottoms: offset Y by -(1.2) + 0.875 = -0.325
    let capsuleRadius: Float = 0.4
    let capsuleHalfHeight: Float = 0.8
    let verticalOffset = -(capsuleHalfHeight + capsuleRadius) + (sensorHeight * 0.5)
    let sensorOffset = vec3(
      forwardX * (sensorDistance + sensorDepth * 0.5), verticalOffset, forwardZ * (sensorDistance + sensorDepth * 0.5))
    let sensorPosition = currentPos + sensorOffset

    // Create rotation quaternion for the box (aligned with player rotation)
    let sensorRotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))

    // Box half extents
    let halfExtents = Vec3(x: sensorWidth * 0.5, y: sensorHeight * 0.5, z: sensorDepth * 0.5)

    return (position: sensorPosition, rotation: sensorRotationQuat, halfExtents: halfExtents)
  }
}
