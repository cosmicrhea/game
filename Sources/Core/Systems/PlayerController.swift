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

    // Create a sensor sphere in front of the capsule for detecting action triggers
    createCapsuleSensor(at: position, rotation: rotation)

    logger.trace("✅ Created character controller at position (\(position.x), \(position.y), \(position.z))")
  }

  /// Create sensor body in front of capsule
  private func createCapsuleSensor(at position: vec3, rotation: Float) {
    guard let physicsWorld = physicsWorld else { return }
    let bodyInterface = physicsWorld.bodyInterface()

    // Create a small sphere sensor in front of the capsule
    // Position it slightly in front and at the same height as the capsule
    let sensorRadius: Float = 0.5
    let sensorDistance: Float = 1.2  // Distance in front of capsule
    let sensorShape = SphereShape(radius: sensorRadius)

    // Position sensor in front of capsule (using forward direction)
    let forwardX = GLMath.sin(rotation)
    let forwardZ = GLMath.cos(rotation)
    let sensorOffset = vec3(forwardX * sensorDistance, 0, forwardZ * sensorDistance)
    let sensorPosition = position + sensorOffset

    // Create body settings - make it a kinematic sensor so it moves with the capsule
    let bodySettings = BodyCreationSettings(
      shape: sensorShape,
      position: RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z),
      rotation: Quat.identity,
      motionType: .kinematic,
      objectLayer: 2  // Same layer as character
    )
    bodySettings.isSensor = true  // Make it a sensor

    // Create and add sensor body
    let sensorBodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
    if sensorBodyID != 0 {
      capsuleSensorBodyID = sensorBodyID
      logger.trace("✅ Created capsule sensor body ID: \(sensorBodyID)")
    } else {
      logger.error("❌ Failed to create capsule sensor")
    }
  }

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

    // Update capsule sensor position to follow the capsule in front
    if let sensorBodyID = capsuleSensorBodyID {
      let bodyInterface = physicsWorld.bodyInterface()

      // Calculate position in front of capsule based on current rotation
      let forwardX = GLMath.sin(rotation)
      let forwardZ = GLMath.cos(rotation)
      let sensorDistance: Float = 1.2
      let sensorOffset = vec3(forwardX * sensorDistance, 0, forwardZ * sensorDistance)
      let sensorPosition = position + sensorOffset

      // Update sensor position using Body wrapper
      var sensorBody = bodyInterface.body(sensorBodyID, in: physicsWorld.getPhysicsSystem())
      sensorBody.position = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)
    }
  }

  /// Clear character controller (when scene changes)
  public func clear() {
    characterController = nil
    capsuleSensorBodyID = nil
  }
}
