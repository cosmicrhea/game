import Foundation
import Jolt

/// Handles action detection, trigger detection, and interaction handling.
@MainActor
public final class InteractionSystem {
  // MARK: - State

  // Currently detected action body name (updated each frame)
  private(set) var detectedActionName: String?
  // Currently detected ledge name (updated each frame)
  private(set) var detectedLedgeName: String?

  // Delayed footstep sound to play after ledge interaction (wait for footsteps trigger to update)
  private var pendingLedgeFootstep: Bool = false

  // Currently active triggers (OrderedSet to avoid duplicates while maintaining order)
  private(set) var currentTriggers: OrderedSet<String> = []
  // Currently active camera triggers (OrderedSet to avoid duplicates while maintaining order)
  private(set) var currentCameraTriggers: OrderedSet<String> = []
  // Currently active footsteps triggers (OrderedSet to avoid duplicates while maintaining order)
  private var currentFootstepsTriggers: OrderedSet<String> = []
  // Previous frame's triggers (to detect new entries)
  private var previousTriggers: Set<String> = []

  // Cached trigger check point for debug visualization
  private var triggerCheckPoint: vec3 = vec3(0, 0, 0)

  // Ledge state tracking (managed by InteractionSystem)
  private var ledgeStates: [String: LedgeState] = [:]

  // MARK: - References

  private weak var physicsWorld: PhysicsWorld?
  private weak var playerController: PlayerController?
  private weak var cameraSystem: CameraSystem?

  // MARK: - Initialization

  public init(
    physicsWorld: PhysicsWorld,
    playerController: PlayerController,
    cameraSystem: CameraSystem
  ) {
    self.physicsWorld = physicsWorld
    self.playerController = playerController
    self.cameraSystem = cameraSystem
  }

  // MARK: - Update

  /// Update interaction system - detect actions and triggers
  func update(sceneScript: Script?, currentAreaName: String?) {
    updateDetectedActions()
    updateDetectedLedges()
    updateLedgeStates()
    updateTriggers(sceneScript: sceneScript, currentAreaName: currentAreaName)
  }

  // MARK: - Update Functions

  /// Update detected action bodies using shape casting
  private func updateDetectedActions() {
    guard let physicsWorld, let playerController else { return }

    // Check for action bodies using shape casting (sweep sensor box forward)
    // Reset to nil first - will be set if we find a contact
    detectedActionName = nil

    // Use shape casting: sweep sensor box from player position forward through sensor depth
    // This might work better with mesh shapes than static collision queries
    let sensorBox = playerController.getSensorBoxTransform()
    let sensorShape = BoxShape(halfExtent: sensorBox.halfExtents)

    // Cast from back edge of sensor box forward through the full sensor box depth
    let playerRotation = playerController.rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Start from the back edge of the sensor box (center - half depth in forward direction)
    let backEdgeOffset = forward * sensorBox.halfExtents.z
    let castStartPosition = sensorBox.position - backEdgeOffset

    // Cast forward by the full depth of the sensor box
    let castDirection = Vec3(x: forwardX * sensorBox.halfExtents.z * 2, y: 0, z: forwardZ * sensorBox.halfExtents.z * 2)

    // Start transform at back edge of sensor box
    let startTransform = RMat44.rotationTranslation(
      rotation: sensorBox.rotation,
      translation: RVec3(x: castStartPosition.x, y: castStartPosition.y, z: castStartPosition.z))
    var castBaseOffset = RVec3(x: castStartPosition.x, y: castStartPosition.y, z: castStartPosition.z)

    // Cast shape forward through sensor box volume
    let castResults = physicsWorld.castShapeAll(
      shape: sensorShape,
      worldTransform: startTransform,
      direction: castDirection,
      baseOffset: &castBaseOffset
    )

    // Check cast results for action bodies
    detectedActionName = nil
    for result in castResults {
      let bodyID = result.bodyID2
      if let actionName = physicsWorld.actionBodyNames[bodyID] {
        // Extract base name from action body name using Scene's extractBaseName
        detectedActionName = Scene.extractBaseName(from: actionName)
        logger.trace("✅ Detected action via shape cast: \(detectedActionName ?? "nil"), fraction: \(result.fraction)")
        break  // Just show first detected action
      }
    }
  }

  /// Update detected ledge bodies using shape casting
  private func updateDetectedLedges() {
    guard let physicsWorld, let playerController else { return }

    // Check cast results for ledge bodies (after action bodies)
    // Use separate ledge sensor box for ledge detection
    detectedLedgeName = nil
    let ledgeSensorBox = playerController.getLedgeSensorBoxTransform()
    let ledgeSensorShape = BoxShape(halfExtent: ledgeSensorBox.halfExtents)

    // Cast from back edge of ledge sensor box forward through the full sensor box depth
    let playerRotation = playerController.rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Start from the back edge of the ledge sensor box (center - half depth in forward direction)
    let ledgeBackEdgeOffset = forward * ledgeSensorBox.halfExtents.z
    let ledgeCastStartPosition = ledgeSensorBox.position - ledgeBackEdgeOffset

    // Cast forward by the full depth of the ledge sensor box
    let ledgeCastDirection = Vec3(
      x: forwardX * ledgeSensorBox.halfExtents.z * 2, y: 0, z: forwardZ * ledgeSensorBox.halfExtents.z * 2)

    // Start transform at back edge of ledge sensor box
    let ledgeStartTransform = RMat44.rotationTranslation(
      rotation: ledgeSensorBox.rotation,
      translation: RVec3(x: ledgeCastStartPosition.x, y: ledgeCastStartPosition.y, z: ledgeCastStartPosition.z))
    var ledgeCastBaseOffset = RVec3(
      x: ledgeCastStartPosition.x, y: ledgeCastStartPosition.y, z: ledgeCastStartPosition.z)

    // Cast shape forward through ledge sensor box volume
    let ledgeCastResults = physicsWorld.castShapeAll(
      shape: ledgeSensorShape,
      worldTransform: ledgeStartTransform,
      direction: ledgeCastDirection,
      baseOffset: &ledgeCastBaseOffset
    )

    // Check ledge cast results for ledge bodies
    for result in ledgeCastResults {
      let bodyID = result.bodyID2
      if let ledgeName = physicsWorld.ledgeBodyNames[bodyID] {
        // Extract base name from ledge body name using Scene's extractBaseName
        detectedLedgeName = Scene.extractBaseName(from: ledgeName)
        logger.trace("✅ Detected ledge via shape cast: \(detectedLedgeName ?? "nil"), fraction: \(result.fraction)")
        break  // Just show first detected ledge
      }
    }
  }

  /// Update ledge states each frame based on player's current Y position
  private func updateLedgeStates() {
    guard let playerController,
      let scene = MainLoop.shared?.scene
    else { return }

    // Player position is capsule center, but high/low nodes are at floor level
    // Convert capsule center to feet position for comparison
    let playerPosition = playerController.position
    let capsuleHalfHeight: Float = 0.8
    let capsuleRadius: Float = 0.4
    let playerFeetY = playerPosition.y - (capsuleHalfHeight + capsuleRadius)

    for ledgeNode in scene.ledgeNodes {
      let ledgeBaseName = Scene.extractBaseName(from: ledgeNode.name)

      // Find high and low child nodes
      var highNode: Node? = nil
      var lowNode: Node? = nil

      func searchChildren(_ node: Node) {
        for child in node.children {
          if scene.hasHint(child, hint: ImportHint.ledgeHigh) {
            highNode = child
          } else if scene.hasHint(child, hint: ImportHint.ledgeLow) {
            lowNode = child
          }
          searchChildren(child)
        }
      }
      searchChildren(ledgeNode)

      // Get high and low Y positions (these are at floor level)
      var highY: Float? = nil
      var lowY: Float? = nil

      if let highNode {
        let highWorldTransform = highNode.calculateWorldTransform()
        highY = highWorldTransform[3].y
      }

      if let lowNode {
        let lowWorldTransform = lowNode.calculateWorldTransform()
        lowY = lowWorldTransform[3].y
      }

      // Determine which state player is closer to (compare feet position to floor positions)
      let calculatedState: LedgeState
      if let highY, let lowY {
        let distanceToHigh = abs(playerFeetY - highY)
        let distanceToLow = abs(playerFeetY - lowY)
        calculatedState = distanceToHigh < distanceToLow ? .high : .low
      } else if highY != nil {
        calculatedState = .high
      } else if lowY != nil {
        calculatedState = .low
      } else {
        // No high/low children found, skip this ledge
        continue
      }

      // Update state in InteractionSystem and physics bodies in PhysicsWorld
      setLedgeState(calculatedState, for: ledgeBaseName)
    }
  }

  /// Get current ledge state
  public func ledgeState(for ledgeName: String) -> LedgeState? {
    return ledgeStates[ledgeName]
  }

  /// Clear all ledge states (called when loading a new scene)
  func clearLedgeStates() {
    ledgeStates.removeAll()
  }

  /// Set ledge state and update physics collision bodies
  private func setLedgeState(_ state: LedgeState, for ledgeName: String) {
    guard let physicsWorld else { return }

    // Store state in InteractionSystem
    ledgeStates[ledgeName] = state

    // Update physics collision bodies
    physicsWorld.updateLedgeCollisionBodies(state: state, for: ledgeName)
  }

  /// Update trigger detection and handling
  private func updateTriggers(sceneScript: Script?, currentAreaName: String?) {
    guard let physicsWorld, let playerController else { return }

    let playerPosition = playerController.position

    // Check for trigger body contacts
    // Triggers fire immediately when player enters them
    currentTriggers.removeAll()
    currentCameraTriggers.removeAll()
    currentFootstepsTriggers.removeAll()
    var newTriggers: Set<String> = []

    // Update trigger collision query every frame
    // Use a point at player position (at player height) instead of a sphere
    // This fixes the bug where triggers at origin always trigger, and is more accurate
    let triggerCheckPoint = RVec3(x: playerPosition.x, y: playerPosition.y, z: playerPosition.z)
    // Cache for debug visualization
    self.triggerCheckPoint = vec3(playerPosition.x, playerPosition.y, playerPosition.z)
    let triggerBodyIDs = physicsWorld.collidePointAll(point: triggerCheckPoint)

    // Check for trigger bodies (use point collision results)
    for bodyID in triggerBodyIDs {
      if let triggerName = physicsWorld.triggerBodyNames[bodyID] {
        // Extract base name from trigger body name using Scene's extractBaseName
        guard let scene = MainLoop.shared?.scene,
          let triggerNode = scene.rootNode.findNode(named: triggerName)
        else { continue }
        let baseName = Scene.extractBaseName(from: triggerName)

        // Check if this is a camera trigger by checking for .cameraTrigger hint
        if scene.hasHint(triggerNode, hint: .cameraTrigger) {
          currentCameraTriggers.append(baseName)
          // Check if we're not already on this camera - switch if needed
          if let cameraSystem = cameraSystem {
            let currentCamera = cameraSystem.selectedCamera
            let needsInitialSync = MainLoop.shared?.shouldForceCameraTriggerSync() ?? false
            let shouldHandleTrigger = currentCamera != baseName || needsInitialSync
            if shouldHandleTrigger {
              cameraSystem.handleCameraTrigger(
                cameraName: baseName,
                currentAreaName: currentAreaName
              )
            }
          }
        } else if scene.hasHint(triggerNode, hint: .footsteps) {
          // Track footsteps trigger
          currentFootstepsTriggers.append(baseName)
          // Handle footsteps trigger - set footstep sound on player controller
          // Base name should match a FootstepSound enum case (e.g., "Metal" -> .metal, "ConcreteEcho" -> .concreteEcho)
          // Convert to camelCase: first letter lowercase, rest as-is
          let camelCaseName = baseName.prefix(1).lowercased() + baseName.dropFirst()
          if let footstepSound = FootstepSound(rawValue: camelCaseName) {
            playerController.setFootstepSound(footstepSound)
          } else if baseName.lowercased() == "default" {
            playerController.setFootstepSound(.default)
          }
        } else {
          currentTriggers.append(baseName)
          newTriggers.insert(baseName)
        }
      }
    }

    // Call trigger methods for newly entered triggers
    let newlyEnteredTriggers = newTriggers.subtracting(previousTriggers)
    for triggerName in newlyEnteredTriggers {
      callTriggerMethod(triggerName: triggerName, sceneScript: sceneScript)
    }

    // Reset footstep sound to default if no footsteps triggers are active
    if currentFootstepsTriggers.isEmpty {
      playerController.setFootstepSound(.default)
    }

    // Play delayed footstep sound after ledge interaction (now that footsteps trigger area has updated)
    if pendingLedgeFootstep {
      pendingLedgeFootstep = false
      UISound.footstep(playerController.footstepSound)
    }

    // Update previous triggers for next frame
    previousTriggers = newTriggers
  }

  // MARK: - Interaction Handling

  /// Handle interaction with detected action
  public func handleInteraction(sceneScript: Script?) {
    guard let detectedActionName = detectedActionName else { return }
    guard let sceneScript = sceneScript else { return }

    // Set the current action name in the script (for variations tracking)
    sceneScript.currentActionName = detectedActionName
    // Reset the call counter for this action (each interaction starts fresh)
    sceneScript.resetCallCounter(for: detectedActionName)

    // Convert action name to method name (e.g., "Stove" -> "stove")
    let methodName = detectedActionName.prefix(1).lowercased() + detectedActionName.dropFirst()

    // Call the method dynamically (handles both sync and async)
    if let task = sceneScript.callMethod(named: methodName) {
      // Async method - fire and forget
      Task {
        await task.value
      }
    } else if type(of: sceneScript).availableMethods().contains(methodName) {
      // Sync method was called successfully
    } else {
      // Method not found
      logger.warning("⚠️ Scene script does not respond to method: \(methodName)")
    }

    // Clear the current action name after the interaction
    sceneScript.currentActionName = nil
  }

  /// Handle interaction with detected ledge
  public func handleLedgeInteraction() {
    guard let detectedLedgeName else { return }
    guard let playerController else { return }

    // Get current ledge state
    guard let currentState = ledgeState(for: detectedLedgeName) else {
      logger.warning("⚠️ Cannot interact with ledge '\(detectedLedgeName)': state not found")
      return
    }

    // Get scene to find ledge high/low nodes
    guard let scene = MainLoop.shared?.scene else {
      logger.warning("⚠️ Cannot interact with ledge: no scene available")
      return
    }

    // Find ledge node and its high/low children
    guard let ledgeNode = scene.ledgeNode(named: detectedLedgeName) else {
      logger.warning("⚠️ Cannot interact with ledge: node '\(detectedLedgeName)' not found")
      return
    }

    var highNode: Node? = nil
    var lowNode: Node? = nil

    func searchChildren(_ node: Node) {
      for child in node.children {
        if scene.hasHint(child, hint: ImportHint.ledgeHigh) {
          highNode = child
        } else if scene.hasHint(child, hint: ImportHint.ledgeLow) {
          lowNode = child
        }
        searchChildren(child)
      }
    }
    searchChildren(ledgeNode)

    // Determine target node based on current state
    let targetNode: Node?
    switch currentState {
    case .high:
      targetNode = lowNode  // Currently high, move to low
    case .low:
      targetNode = highNode  // Currently low, move to high
    }

    guard let targetNode else {
      logger.warning("⚠️ Cannot interact with ledge: target node not found for state \(currentState)")
      return
    }

    // Get target position from target node
    let targetWorldTransform = targetNode.calculateWorldTransform()
    let targetY = targetWorldTransform[3].y

    // Preserve player's current X and Z position (stay at the same horizontal position where they interacted)
    let currentPosition = playerController.position
    let targetX = currentPosition.x
    let targetZ = currentPosition.z

    // Calculate forward direction from player
    let playerRotation = playerController.rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Move one and a half player depth (capsule radius = 0.4) forward in X/Z
    let playerDepth: Float = 0.6
    let finalX = targetX + forward.x * playerDepth
    let finalZ = targetZ + forward.z * playerDepth

    // For Y position: use target node's Y, but adjust for capsule dimensions
    // Capsule: radius 0.4, halfHeight 0.8
    // Bottom of capsule is at center - (halfHeight + radius) = center - 1.2
    // So: center = surface + 1.2 (where surface is where the player's feet should be)
    // The target node Y represents the surface/floor level where we want the player's feet to be
    // We need to add (halfHeight + radius) = 1.2 to get the center position
    let capsuleHalfHeight: Float = 0.8
    let capsuleRadius: Float = 0.4
    let finalY = targetY + capsuleHalfHeight + capsuleRadius

    let finalPosition = vec3(finalX, finalY, finalZ)

    // Teleport player to final position (keep current rotation)
    playerController.setPosition(finalPosition, rotation: playerRotation)

    // Calculate new state based on player's new position and update immediately
    // Player is now at targetY, so calculate which state they're closer to
    let playerFeetY = finalY - (capsuleHalfHeight + capsuleRadius)
    
    // Get high and low Y positions for comparison
    var highY: Float? = nil
    var lowY: Float? = nil
    
    if let highNode {
      let highWorldTransform = highNode.calculateWorldTransform()
      highY = highWorldTransform[3].y
    }
    
    if let lowNode {
      let lowWorldTransform = lowNode.calculateWorldTransform()
      lowY = lowWorldTransform[3].y
    }
    
    // Determine new state based on player's new position
    let newState: LedgeState
    if let highY, let lowY {
      let distanceToHigh = abs(playerFeetY - highY)
      let distanceToLow = abs(playerFeetY - lowY)
      newState = distanceToHigh < distanceToLow ? .high : .low
    } else if highY != nil {
      newState = .high
    } else if lowY != nil {
      newState = .low
    } else {
      // Fallback: toggle state
      newState = currentState == .high ? .low : .high
    }
    
    // Update state and collision bodies immediately
    setLedgeState(newState, for: detectedLedgeName)

    // Schedule footstep sound to play next frame (after footsteps trigger area updates)
    pendingLedgeFootstep = true

    logger.trace(
      "🔧 Interacted with ledge '\(detectedLedgeName)': \(currentState) -> \(newState), teleported to \(finalPosition)")
  }

  // MARK: - Trigger Methods

  private func callTriggerMethod(triggerName: String, sceneScript: Script?) {
    guard let sceneScript = sceneScript else { return }

    // Convert trigger name to method name (e.g., "Door" -> "door")
    let methodName = triggerName.prefix(1).lowercased() + triggerName.dropFirst()

    // Call the method dynamically (handles both sync and async)
    if let task = sceneScript.callMethod(named: methodName) {
      // Async method - fire and forget
      Task {
        await task.value
      }
    } else if type(of: sceneScript).availableMethods().contains(methodName) {
      // Sync method was called successfully
    } else {
      // Method not found
      logger.warning("⚠️ Scene script does not respond to trigger method: \(methodName)")
    }
  }

  // MARK: - Debug Visualization

  /// Draw debug visualization for trigger detection
  public func drawDebug(
    debugRenderer: DebugRenderer?,
    projection: mat4,
    view: mat4
  ) {
    guard let debugRenderer, let physicsWorld else { return }

    // Draw a vertical line at the trigger check point (from slightly below to slightly above player height)
    // This helps visualize where the point collision check is happening
    let lineHeight: Float = 1.0  // Half height above and below (total 2.0 units tall)
    let lineStart = vec3(triggerCheckPoint.x, triggerCheckPoint.y - lineHeight, triggerCheckPoint.z)
    let lineEnd = vec3(triggerCheckPoint.x, triggerCheckPoint.y + lineHeight, triggerCheckPoint.z)

    // Use the debug renderer implementation to draw the line
    if let debugRendererImpl = physicsWorld.getDebugRendererImplementation() {
      // Draw vertical line in bright green to show trigger check point
      debugRendererImpl.drawLine(
        from: RVec3(x: lineStart.x, y: lineStart.y, z: lineStart.z),
        to: RVec3(x: lineEnd.x, y: lineEnd.y, z: lineEnd.z),
        color: 0xFF00FFFF  // Green in ABGR format
      )

      // Draw a larger marker at the exact point
      debugRenderer.drawMarker(
        RVec3(x: triggerCheckPoint.x, y: triggerCheckPoint.y, z: triggerCheckPoint.z),
        color: 0xFF00FFFF,  // Green
        size: 0.5  // Larger size to be more visible
      )
    } else {
      logger.trace("⚠️ drawDebug: debugRendererImpl is nil")
    }
  }
}
