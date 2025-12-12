import Foundation
import Jolt

/// Handles action detection, trigger detection, and interaction handling.
@MainActor
public final class InteractionSystem {
  // MARK: - State

  // Currently detected action body name (updated each frame)
  private(set) var detectedActionName: String?

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
  func update(
    sceneScript: Script?,
    currentAreaName: String?
  ) {
    guard let physicsWorld = physicsWorld,
      let playerController = playerController
    else { return }

    let playerPosition = playerController.position
    let characterController = playerController.getCharacterController()  // Used for trigger detection below

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

    // // Debug: print all cast results
    // if !castResults.isEmpty {
    //   logger.debug("🔍 Shape cast found \(castResults.count) bodies:")
    //   let bodyInterface = physicsWorld.bodyInterface()
    //   for (index, result) in castResults.enumerated() {
    //     let bodyID = result.bodyID2
    //     let bodyName = physicsWorld.getBodyName(bodyID)
    //     let isAction = physicsWorld.actionBodyNames[bodyID] != nil
    //     let body = bodyInterface.body(bodyID, in: physicsWorld.getPhysicsSystem())
    //     let objectLayer = body.objectLayer
    //     let bodyPos = body.position
    //     logger.debug(
    //       "  [\(index)] BodyID: \(bodyID), name: \(bodyName), layer: \(objectLayer), isAction: \(isAction), pos: (\(bodyPos.x), \(bodyPos.y), \(bodyPos.z)), fraction: \(result.fraction)"
    //     )
    //   }
    // } else {
    //   logger.debug("🔍 Shape cast found 0 bodies")
    // }

    // Check cast results for action bodies
    for result in castResults {
      let bodyID = result.bodyID2
      if let actionName = physicsWorld.actionBodyNames[bodyID] {
        // Extract base name from action body name using Scene's extractBaseName
        detectedActionName = Scene.extractBaseName(from: actionName)
        logger.trace("✅ Detected action via shape cast: \(detectedActionName ?? "nil"), fraction: \(result.fraction)")
        break  // Just show first detected action
      }
    }

    // OLD APPROACH: Sensor body contacts (keeping commented for reference)
    /*
    if let sensorBodyID = playerController.getSensorBodyID() {
      let contacts = physicsWorld.getSensorBodyContacts(sensorBodyID: sensorBodyID)
    
      // Debug: print all sensor contacts with front-facing info
      if !contacts.isEmpty {
        logger.debug("🔍 Sensor body contacts: \(contacts.count) bodies")
        let bodyInterface = physicsWorld.bodyInterface()
        let playerRotation = playerController.rotation
          let forwardX = GLMath.sin(playerRotation)
          let forwardZ = GLMath.cos(playerRotation)
        let playerForward = vec3(forwardX, 0, forwardZ)
        let sensorBox = playerController.getSensorBoxTransform()
        let sensorBoxCenter = sensorBox.position
    
        for (index, contactBodyID) in contacts.enumerated() {
          let bodyName = physicsWorld.getBodyName(contactBodyID)
          let isAction = physicsWorld.actionBodyNames[contactBodyID] != nil
          var body = bodyInterface.body(contactBodyID, in: physicsWorld.getPhysicsSystem())
          let objectLayer = body.objectLayer
          let bodyPos = body.position
    
          // Calculate dot product for debug
          let toAction = vec3(
            bodyPos.x - sensorBoxCenter.x,
            bodyPos.y - sensorBoxCenter.y,
            bodyPos.z - sensorBoxCenter.z
          )
          let distance = length(toAction)
          let dotProduct = distance > 0.001 ? dot(playerForward, normalize(toAction)) : 0
          let isInFront = dotProduct > -0.5
    
          logger.debug(
            "  [\(index)] BodyID: \(contactBodyID), name: \(bodyName), layer: \(objectLayer), isAction: \(isAction), pos: (\(bodyPos.x), \(bodyPos.y), \(bodyPos.z)), dot: \(dotProduct), inFront: \(isInFront)"
          )
        }
      }
    
      // Check contacts for action bodies, but only if they're in front of the player
      let playerRotation = playerController.rotation
      let forwardX = GLMath.sin(playerRotation)
      let forwardZ = GLMath.cos(playerRotation)
      let playerForward = vec3(forwardX, 0, forwardZ)
    
      // Get sensor box center for more accurate front-facing check
      let sensorBox = playerController.getSensorBoxTransform()
      let sensorBoxCenter = sensorBox.position
    
      for contactBodyID in contacts {
        if let actionName = physicsWorld.actionBodyNames[contactBodyID] {
          // Check if action body is in front of player (not behind)
          let bodyInterface = physicsWorld.bodyInterface()
          var actionBody = bodyInterface.body(contactBodyID, in: physicsWorld.getPhysicsSystem())
          let actionBodyPos = actionBody.position
    
          // Calculate direction from sensor box center to action body center
          // This is more accurate since the sensor box is in front of the player
          let toAction = vec3(
            actionBodyPos.x - sensorBoxCenter.x,
            actionBodyPos.y - sensorBoxCenter.y,
            actionBodyPos.z - sensorBoxCenter.z
          )
          let distanceToAction = length(toAction)
    
          // Skip if too far (sanity check)
          guard distanceToAction > 0.001 else { continue }
    
          let toActionNormalized = toAction / distanceToAction
    
          // Dot product: positive means in front, negative means behind
          // Use a lenient threshold (-0.5) to allow actions that are mostly in front
          // This means we allow up to ~120 degrees in front (cos(120°) = -0.5)
          // But we still reject things directly behind (cos(180°) = -1.0)
          let dotProduct = dot(playerForward, toActionNormalized)
    
          // Only detect if action is in front (dot product > -0.5 means roughly in front 120-degree cone)
          // This allows actions that are mostly in front, but rejects things directly behind
          // TEMP: Disable front-facing check to test if sensor contacts work
          // if dotProduct > -0.5 {
          if true {  // TEMP: Always detect to test sensor body contacts
            // Extract base name from action body name using Scene's extractBaseName
            detectedActionName = Scene.extractBaseName(from: actionName)
            logger.debug(
              "✅ Detected action via sensor body (front-facing): \(detectedActionName ?? "nil"), dot: \(dotProduct), dist: \(distanceToAction)"
            )
            break  // Just show first detected action
          } else {
            logger.debug("🚫 Action body \(actionName) is behind player (dot: \(dotProduct) <= -0.5), ignoring")
          }
        }
      }
    }
    */

    // FALLBACK COMMENTED OUT: Character controller contacts (only using sensor body contacts now)
    // if detectedActionName == nil, let characterController {
    //   let contacts = characterController.activeContacts()
    //   for contact in contacts {
    //     // Action bodies are sensors again, so check isSensorB for them
    //     // Trigger bodies are also sensors
    //     if contact.isSensorB, let actionName = physicsWorld.actionBodyNames[contact.bodyID] {
    //       // Extract base name from action body name using scene's extractBaseName
    //       if let scene = MainLoop.shared?.scene {
    //         detectedActionName = scene.extractBaseName(from: actionName)
    //       } else {
    //         // Fallback: remove -action suffix if scene not available
    //         detectedActionName = actionName.replacing(/-action$/, with: "")
    //       }
    //       break  // Just show first detected action
    //     }
    //   }
    // }

    // Check for trigger body contacts
    // Triggers fire immediately when player enters them
    currentTriggers.removeAll()
    currentCameraTriggers.removeAll()
    currentFootstepsTriggers.removeAll()
    var newTriggers: Set<String> = []

    // // Check character controller contacts for triggers (always check these, they're fast)
    // if let characterController {
    //   let contacts = characterController.activeContacts()
    //   for contact in contacts {
    //     if contact.isSensorB, let triggerName = physicsWorld.triggerBodyNames[contact.bodyID] {
    //       // Extract base name from trigger body name using Scene's extractBaseName
    //       guard let scene = MainLoop.shared?.scene,
    //         let triggerNode = scene.rootNode.findNode(named: triggerName)
    //       else { continue }
    //       let baseName = Scene.extractBaseName(from: triggerName)

    //       // Check if this is a camera trigger by checking for .cameraTrigger hint
    //       if scene.hasHint(triggerNode, hint: .cameraTrigger) {
    //         currentCameraTriggers.append(baseName)
    //         // Check if we're not already on this camera - switch if needed
    //         if let cameraSystem = cameraSystem {
    //           let currentCamera = cameraSystem.selectedCamera
    //           let needsInitialSync = MainLoop.shared?.shouldForceCameraTriggerSync() ?? false
    //           let shouldHandleTrigger = currentCamera != baseName || needsInitialSync
    //           if shouldHandleTrigger {
    //             cameraSystem.handleCameraTrigger(
    //               cameraName: baseName,
    //               currentAreaName: currentAreaName
    //             )
    //           }
    //         }
    //       } else if scene.hasHint(triggerNode, hint: .footsteps) {
    //         // Track footsteps trigger
    //         currentFootstepsTriggers.append(baseName)
    //         // Handle footsteps trigger - set footstep sound on player controller
    //         // Base name should match a FootstepSound enum case (e.g., "Metal" -> .metal, "ConcreteEcho" -> .concreteEcho)
    //         // Convert to camelCase: first letter lowercase, rest as-is
    //         let camelCaseName = baseName.prefix(1).lowercased() + baseName.dropFirst()
    //         if let footstepSound = FootstepSound(rawValue: camelCaseName) {
    //           playerController.setFootstepSound(footstepSound)
    //         } else if baseName.lowercased() == "default" {
    //           playerController.setFootstepSound(.default)
    //         }
    //       } else {
    //         currentTriggers.append(baseName)
    //         newTriggers.insert(baseName)
    //       }
    //     }
    //   }
    // }

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
    guard let debugRenderer = debugRenderer,
      let physicsWorld = physicsWorld
    else { return }

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
