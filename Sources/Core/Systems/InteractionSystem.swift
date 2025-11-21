import CJolt
import Foundation
import Jolt

/// Handles action detection, trigger detection, and interaction handling
@MainActor
public final class InteractionSystem {
  // MARK: - State

  // Currently detected action body name (updated each frame)
  private(set) var detectedActionName: String?

  // Currently active triggers (OrderedSet to avoid duplicates while maintaining order)
  private(set) var currentTriggers: OrderedSet<String> = []
  // Currently active camera triggers (OrderedSet to avoid duplicates while maintaining order)
  private(set) var currentCameraTriggers: OrderedSet<String> = []
  // Previous frame's triggers (to detect new entries)
  private var previousTriggers: Set<String> = []

  // Query caching - reduces expensive collision queries
  private var queryFrameCounter: UInt32 = 0  // For caching collision queries
  private var cachedActionQueryResults: [JPH_CollideShapeResult] = []  // Cached action query results
  private var cachedTriggerQueryResults: [JPH_CollideShapeResult] = []  // Cached trigger query results
  private let queryCacheInterval: UInt32 = 2  // Run queries every 2 frames (30fps effective rate)

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
    normalizedAreaIdentifier: (String) -> String
  ) {
    guard let physicsWorld = physicsWorld,
      let playerController = playerController
    else { return }

    let playerPosition = playerController.position
    let playerRotation = playerController.rotation
    let characterController = playerController.getCharacterController()

    // FIX 3: Cache collision queries - only run every N frames
    queryFrameCounter += 1
    let shouldUpdateQueries = (queryFrameCounter % queryCacheInterval) == 0

    // Check for action body contacts (sensor bodies)
    detectedActionName = nil

    // Also check character controller contacts (always check these, they're fast)
    if let characterController {
      let contacts = characterController.activeContacts()
      for contact in contacts {
        if contact.isSensorB, let actionName = physicsWorld.actionBodyNames[contact.bodyID] {
          detectedActionName = actionName.replacing(/-action$/, with: "")
          break  // Just show first detected action
        }
      }

      // Check for action body overlaps using collision query (sensor position is updated by PlayerController)
      if playerController.getSensorBodyID() != nil {
        // FIX 3: Only query for overlapping action bodies every N frames
        if shouldUpdateQueries {
          // Calculate position in front of capsule based on current rotation
          let forwardX = GLMath.sin(playerRotation)
          let forwardZ = GLMath.cos(playerRotation)
          let sensorDistance: Float = 1.2
          let sensorOffset = vec3(forwardX * sensorDistance, 0, forwardZ * sensorDistance)
          let sensorPosition = playerPosition + sensorOffset

          let sensorShape = SphereShape(radius: 0.5)
          var baseOffset = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)
          cachedActionQueryResults = physicsWorld.collideShapeAll(
            shape: sensorShape,
            scale: Vec3(x: 1, y: 1, z: 1),
            baseOffset: &baseOffset
          )
        }

        // Check if any of the colliding bodies are action bodies (use cached results)
        for result in cachedActionQueryResults {
          let bodyID = result.bodyID2
          if let actionName = physicsWorld.actionBodyNames[bodyID] {
            detectedActionName = actionName.replacing(/-action$/, with: "")
            break  // Just show first detected action
          }
        }
      }

      // Check for trigger body contacts
      // Triggers fire immediately when player enters them
      currentTriggers.removeAll()
      currentCameraTriggers.removeAll()
      var newTriggers: Set<String> = []

      // Check character controller contacts for triggers (always check these, they're fast)
      for contact in contacts {
        if contact.isSensorB, let triggerName = physicsWorld.triggerBodyNames[contact.bodyID] {
          // Handle camera triggers
          if triggerName.hasPrefix("CameraTrigger_") {
            let cameraName = String(triggerName.dropFirst("CameraTrigger_".count))
            currentCameraTriggers.append(cameraName)
            // Check if we're not already on this camera - switch if needed
            if let cameraSystem = cameraSystem {
              let currentCamera = cameraSystem.selectedCamera
              if currentCamera != cameraName {
                cameraSystem.handleCameraTrigger(
                  cameraName: cameraName,
                  sceneScript: sceneScript,
                  normalizedAreaIdentifier: normalizedAreaIdentifier
                )
              }
            }
          } else {
            let cleanName = triggerName.replacing(/-trigger$/, with: "")
            currentTriggers.append(cleanName)
            newTriggers.insert(cleanName)
          }
        }
      }

      // FIX 3: Only check using collision query every N frames
      if shouldUpdateQueries {
        let triggerCheckRadius: Float = 0.5  // Radius to check around player
        let triggerCheckShape = SphereShape(radius: triggerCheckRadius)
        var playerBaseOffset = RVec3(x: playerPosition.x, y: playerPosition.y, z: playerPosition.z)
        cachedTriggerQueryResults = physicsWorld.collideShapeAll(
          shape: triggerCheckShape,
          scale: Vec3(x: 1, y: 1, z: 1),
          baseOffset: &playerBaseOffset
        )
      }

      // Check for trigger bodies (use cached results)
      for result in cachedTriggerQueryResults {
        let bodyID = result.bodyID2
        if let triggerName = physicsWorld.triggerBodyNames[bodyID] {
          // Handle camera triggers
          if triggerName.hasPrefix("CameraTrigger_") {
            let cameraName = String(triggerName.dropFirst("CameraTrigger_".count))
            currentCameraTriggers.append(cameraName)
            // Check if we're not already on this camera - switch if needed
            if let cameraSystem = cameraSystem {
              let currentCamera = cameraSystem.selectedCamera
              if currentCamera != cameraName {
                cameraSystem.handleCameraTrigger(
                  cameraName: cameraName,
                  sceneScript: sceneScript,
                  normalizedAreaIdentifier: normalizedAreaIdentifier
                )
              }
            }
          } else {
            let cleanName = triggerName.replacing(/-trigger$/, with: "")
            currentTriggers.append(cleanName)
            newTriggers.insert(cleanName)
          }
        }
      }

      // Call trigger methods for newly entered triggers
      let newlyEnteredTriggers = newTriggers.subtracting(previousTriggers)
      for triggerName in newlyEnteredTriggers {
        callTriggerMethod(triggerName: triggerName, sceneScript: sceneScript)
      }

      // Update previous triggers for next frame
      previousTriggers = newTriggers
    }
  }

  // MARK: - Interaction Handling

  /// Handle interaction with detected action
  func handleInteraction(sceneScript: Script?) {
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
}
