import Assimp
import CJolt
import Foundation
import Jolt
//import ObjectiveC.runtime

private let startingScene = "shooting_range"
private let startingEntry = "range"

@Editable final class MainLoop: RenderLoop {
  static var shared: MainLoop?

  // Scene configuration
  private(set) var sceneName: String = startingScene

  // Gameplay state
  private(set) var playerPosition: vec3 = vec3(0, 0, 0)
  private(set) var playerRotation: Float = 0.0
  private var moveSpeed: Float = 3.0
  private var rotationSpeed: Float = 2.0  // radians per second
  private var smoothedFPS: Float = 60.0
  private var spawnPosition: vec3 = vec3(0, 0, 0)
  private var spawnRotation: Float = 0.0

  // Capsule mesh from GLB file
  private var capsuleMeshInstances: [MeshInstance] = []

  // Foreground meshes from scene (nodes with -fg suffix)
  private var foregroundMeshInstances: [MeshInstance] = []

  // Capsule height offset - adjust if capsule origin is at center instead of bottom
  @Editor(0.0...2.0) var capsuleHeightOffset: Float = 1.2

  // Footstep tracking
  private var footstepAccumulatedDistance: Float = 0.0
  private var previousPlayerPosition: vec3 = vec3(0, 0, 0)
  private let footstepDistanceWalk: Float = 1.2  // Distance between footsteps when walking
  private let footstepDistanceRun: Float = 1.5  // Distance between footsteps when running (faster rate)

  // Debug renderer for physics visualization
  private var debugRenderer: DebugRenderer?
  private var physicsSystem: PhysicsSystem
  // Job system for physics updates (required, cannot be null)
  private var jobSystem: JobSystemThreadPool
  // Store filter objects so they stay alive (PhysicsSystem only keeps references)
  private var broadPhaseLayerInterface: BroadPhaseLayerInterfaceTable
  private var objectLayerPairFilter: ObjectLayerPairFilterTable
  private var objectVsBroadPhaseLayerFilter: ObjectVsBroadPhaseLayerFilterTable
  // Character controller for player capsule
  private var characterController: CharacterVirtual?
  // Tracking all physics body IDs for the current scene (so we can clear them when loading a new scene)
  private var collisionBodyIDs: [BodyID] = []
  // Mapping from action body IDs to their node names
  private var actionBodyNames: [BodyID: String] = [:]
  // Currently detected action body name (updated each frame)
  private var detectedActionName: String?
  // Mapping from trigger body IDs to their node names
  private var triggerBodyNames: [BodyID: String] = [:]
  // Currently active triggers (OrderedSet to avoid duplicates while maintaining order)
  private var currentTriggers: OrderedSet<String> = []
  // Currently active camera triggers (OrderedSet to avoid duplicates while maintaining order)
  private var currentCameraTriggers: OrderedSet<String> = []
  // Previous frame's triggers (to detect new entries)
  private var previousTriggers: Set<String> = []
  // Sensor body in front of capsule for detecting action triggers
  private var capsuleSensorBodyID: BodyID?
  // Flag to track if physics system is ready for updates
  private var physicsSystemReady: Bool = false
  var currentProjection: mat4 = mat4(1)  // Accessible by debug renderer implementation
  var currentView: mat4 = mat4(1)  // Accessible by debug renderer implementation

  // Query caching - reduces expensive collision queries
  private var queryFrameCounter: UInt32 = 0  // For caching collision queries
  private var cachedActionQueryResults: [JPH_CollideShapeResult] = []  // Cached action query results
  private var cachedTriggerQueryResults: [JPH_CollideShapeResult] = []  // Cached trigger query results
  private let queryCacheInterval: UInt32 = 2  // Run queries every 2 frames (30fps effective rate)

  // Debug camera override mode - when enabled, camera triggers are ignored
  private var isDebugCameraOverrideMode: Bool = false

  @Editor var visualizePhysics: Bool = false
  @Editor var visualizeEntries: Bool = false
  @Editor var disableDepth: Bool = false

  @Editor func shakeScreen() { ScreenShake.shared.shake(.subtle) }
  @Editor func shakeScreenMore() { ScreenShake.shared.shake(.heavy) }
  @Editor func shakeScreenVertically() { ScreenShake.shared.shake(.subtle, axis: .vertical) }

  // Scene and camera
  private(set) var scene: Scene?
  private var camera: Assimp.Camera?
  private var cameraNode: Node?
  private var cameraWorldTransform: mat4 = mat4(1)

  // Scene lights
  private var sceneLights: [(light: Assimp.Light, worldTransform: mat4)] = []

  // Prerendered environment renderer
  private var prerenderedEnvironment: PrerenderedEnvironment?

  // Weapon system
  private var weaponSystem: WeaponSystem

  //@Editable
  var nearestNeighbor: Bool = true {
    didSet {
      prerenderedEnvironment?.nearestNeighborFiltering = nearestNeighbor
    }
  }

  // @Editable
  var selectedCamera: String = "1" {
    didSet {
      if selectedCamera != oldValue {
        try? prerenderedEnvironment?.switchToCamera(selectedCamera)
      }
    }
  }

  // Main menu system
  private let mainMenu: MainMenu
  private var showingMainMenu: Bool = false

  // Pickup view system
  private var pickupView: PickupView?
  private var showingPickupView: Bool = false

  // Dialog system
  private(set) var dialogView: DialogView!
  // Scene script instance
  private var sceneScript: Script?

  // Room boundaries
  private let roomSize: Float = 10.0
  private var restrictMovementToRoom: Bool = false
  private let boxSize: Float = 2.0
  private let boxPosition: vec3 = vec3(3, 0, 3)

  init() {
    // Initialize dialog view
    dialogView = DialogView()

    // Initialize main menu
    mainMenu = MainMenu()

    // Initialize weapon system
    weaponSystem = WeaponSystem(
      inventory: Inventory.player1,
      slotGrid: mainMenu.inventoryView.slotGrid
    )

    // Register all scene scripts (auto-generated by build tool)
    // This registers factory functions - they'll be called lazily when scripts are created
    registerAllSceneScripts()

    // Initialize Jolt runtime (required before using any Jolt features)
    JoltRuntime.initialize()

    // Initialize physics system for collision body visualization
    // Set up collision filtering (required for PhysicsSystem)
    // Note: Object layers are 0-indexed, so numObjectLayers: 3 means we can use layers 0, 1, 2
    let numObjectLayers: UInt32 = 3  // 0=unused, 1=static, 2=dynamic
    let numBroadPhaseLayers: UInt32 = 2  // Keep it simple - 2 broad phase layers

    // Create broad phase layer interface
    broadPhaseLayerInterface = BroadPhaseLayerInterfaceTable(
      numObjectLayers: numObjectLayers,
      numBroadPhaseLayers: numBroadPhaseLayers
    )
    // Map all object layers to the first broad phase layer (simple setup)
    broadPhaseLayerInterface.map(objectLayer: 1, to: 0)  // Static objects
    broadPhaseLayerInterface.map(objectLayer: 2, to: 0)  // Dynamic objects (if we add them)

    // Create object layer pair filter (allows all collisions)
    objectLayerPairFilter = ObjectLayerPairFilterTable(numObjectLayers: numObjectLayers)
    // Enable collisions between all layers
    objectLayerPairFilter.enableCollision(1, 1)  // Static vs Static
    objectLayerPairFilter.enableCollision(1, 2)  // Static vs Dynamic
    objectLayerPairFilter.enableCollision(2, 2)  // Dynamic vs Dynamic

    // Create object vs broad phase layer filter
    objectVsBroadPhaseLayerFilter = ObjectVsBroadPhaseLayerFilterTable(
      broadPhaseLayerInterface: broadPhaseLayerInterface,
      numBroadPhaseLayers: numBroadPhaseLayers,
      objectLayerPairFilter: objectLayerPairFilter,
      numObjectLayers: numObjectLayers
    )

    // Create job system for physics updates (required for PhysicsSystem::Update)
    jobSystem = JobSystemThreadPool(
      maxJobs: 1024,
      maxBarriers: 8,
      numThreads: -1  // Auto-detect number of threads
    )

    // Create physics system with proper filters
    physicsSystem = PhysicsSystem(
      maxBodies: 1024,
      broadPhaseLayerInterface: broadPhaseLayerInterface,
      objectLayerPairFilter: objectLayerPairFilter,
      objectVsBroadPhaseLayerFilter: objectVsBroadPhaseLayerFilter
    )
    physicsSystem.setGravity(Vec3(x: 0, y: -9.81, z: 0))

    // Initialize debug renderer
    let debugProcs = DebugRendererImplementation()
    debugRenderer = DebugRenderer(procs: debugProcs)
    debugProcs.renderLoop = self

    // Create ground plane immediately (doesn't depend on scene)
    createGroundPlane()

    // Load capsule mesh
    loadCapsuleMesh()

    // Set shared instance (after all properties are initialized)
    // Used by @SceneScript macro to access scene and dialogView
    MainLoop.shared = self

    // Load starting scene
    Task {
      await loadScene(startingScene, entry: startingEntry)
    }
  }

  /// Load scene lights and their world transforms
  private func loadSceneLights() {
    guard let scene = self.scene else { return }
    sceneLights.removeAll()

    for light in scene.lights {
      guard let lightName = light.name else { continue }

      // Find the node with the same name as the light
      if let lightNode = scene.rootNode.findNode(named: lightName) {
        let worldTransform = calculateNodeWorldTransform(lightNode, scene: scene)
        sceneLights.append((light: light, worldTransform: worldTransform))
        logger.trace("💡 Loaded light '\(lightName)' type: \(light.type)")
      } else {
        logger.warning("⚠️ Light node '\(lightName)' not found in scene graph")
      }
    }

    if sceneLights.isEmpty {
      logger.warning("⚠️ No lights found in scene")
    }
  }

  /// Load foreground meshes from nodes with -fg suffix (recursively includes subnodes)
  private func loadForegroundMeshes(scene: Scene) {
    foregroundMeshInstances.removeAll()

    func traverse(_ node: Node) {
      // Check if this node has -fg suffix
      if let name = node.name, name.hasSuffix("-fg") {
        // Get all meshes from this node (create MeshInstance regardless of isHidden)
        // Visibility is checked at render time
        for i in 0..<node.numberOfMeshes {
          let meshIndex = node.meshes[i]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Only create instance if mesh has vertices
            guard mesh.numberOfVertices > 0 else { continue }

            // Get transform matrix for this mesh
            let transformMatrix = scene.getTransformMatrix(for: mesh)

            // Create MeshInstance (reusing existing init!)
            let meshInstance = MeshInstance(
              scene: scene,
              mesh: mesh,
              transformMatrix: transformMatrix,
              sceneIdentifier: scene.filePath
            )

            // Store node reference for checking visibility at render time
            meshInstance.node = node

            foregroundMeshInstances.append(meshInstance)
            logger.trace("✅ Created foreground MeshInstance for node '\(name)' mesh \(i)")
          }
        }
      }

      // Recursively traverse children (even if this node doesn't have -fg, children might)
      for child in node.children {
        traverse(child)
      }
    }

    traverse(scene.rootNode)
    logger.trace("✅ Loaded \(foregroundMeshInstances.count) foreground mesh instances")
  }

  /// Get lighting from scene lights (returns main light and fill light)
  private func getSceneLighting() -> (
    mainLight: (direction: vec3, color: vec3, intensity: Float),
    fillLight: (direction: vec3, color: vec3, intensity: Float)
  ) {
    // Default lighting
    var mainLight = (direction: vec3(0, -1, 0), color: vec3(1, 1, 1), intensity: Float(1.0))
    var fillLight = (direction: vec3(-0.3, -0.5, -0.2), color: vec3(0.8, 0.9, 1.0), intensity: Float(0.4))

    // Use first directional light as main light
    if let firstDirectionalLight = sceneLights.first(where: { $0.light.type == .directional }) {
      let light = firstDirectionalLight.light
      let worldTransform = firstDirectionalLight.worldTransform

      // Transform light direction to world space
      // Light direction is in local space, transform it using the rotation part of the world transform
      let localDir = vec3(light.direction.x, light.direction.y, light.direction.z)
      // Extract rotation matrix (first 3x3) and transform the direction
      let rotMatrix = mat3(
        vec3(worldTransform[0].x, worldTransform[0].y, worldTransform[0].z),
        vec3(worldTransform[1].x, worldTransform[1].y, worldTransform[1].z),
        vec3(worldTransform[2].x, worldTransform[2].y, worldTransform[2].z)
      )
      let worldDir = normalize(rotMatrix * localDir)

      // Use negative direction (light points toward negative direction)
      mainLight.direction = -worldDir
      mainLight.color = vec3(light.colorDiffuse.x, light.colorDiffuse.y, light.colorDiffuse.z)
      mainLight.intensity = 1.0

      logger.trace(
        "💡 Using directional light '\(light.name ?? "unnamed")' - direction: \(mainLight.direction), color: \(mainLight.color)"
      )
    }

    // Use second directional light or first point light as fill light if available
    if sceneLights.count > 1 {
      let secondLight = sceneLights[1]
      let light = secondLight.light
      let worldTransform = secondLight.worldTransform

      if light.type == .directional {
        let localDir = vec3(light.direction.x, light.direction.y, light.direction.z)
        let rotMatrix = mat3(
          vec3(worldTransform[0].x, worldTransform[0].y, worldTransform[0].z),
          vec3(worldTransform[1].x, worldTransform[1].y, worldTransform[1].z),
          vec3(worldTransform[2].x, worldTransform[2].y, worldTransform[2].z)
        )
        let worldDir = normalize(rotMatrix * localDir)
        fillLight.direction = -worldDir
      } else if light.type == .point {
        // For point lights, calculate direction from light position to player
        let lightPos = vec3(worldTransform[3].x, worldTransform[3].y, worldTransform[3].z)
        let toPlayer = normalize(playerPosition - lightPos)
        fillLight.direction = toPlayer
      }

      fillLight.color = vec3(light.colorDiffuse.x, light.colorDiffuse.y, light.colorDiffuse.z)
      fillLight.intensity = 0.4
    }

    return (mainLight, fillLight)
  }

  /// Syncs `camera`, its node/world transform and prerender near/far from the given camera name
  private func syncActiveCamera(name: String) {
    guard let scene = self.scene else { return }
    let nodeName = name
    if let node = scene.rootNode.findNode(named: nodeName) {
      cameraNode = node
      cameraWorldTransform = calculateNodeWorldTransform(node, scene: scene)
      logger.trace("✅ Active camera node: \(nodeName)")
      // Debug: Print camera transform
      let cameraPos = vec3(cameraWorldTransform[3].x, cameraWorldTransform[3].y, cameraWorldTransform[3].z)
      logger.trace("📷 Camera world transform position: \(cameraPos)")
    } else {
      logger.warning("⚠️ Camera node not found: \(nodeName)")
      cameraNode = nil
      cameraWorldTransform = mat4(1)
    }

    if let cam = scene.cameras.first(where: { $0.name == nodeName }) {
      camera = cam
      // Sync projection and mist params
      prerenderedEnvironment?.near = cam.clipPlaneNear
      prerenderedEnvironment?.far = cam.clipPlaneFar
      // If Blender mist settings are known, keep defaults (0.1 / 25.0) or adjust here
      logger.trace(
        "✅ Active camera params near=\(cam.clipPlaneNear) far=\(cam.clipPlaneFar) fov=\(cam.horizontalFOV) aspect=\(cam.aspect)"
      )
    } else {
      logger.warning("⚠️ Camera struct not found for name: \(nodeName)")
      camera = nil
    }
  }

  private func loadCapsuleMesh() {
    Task {
      do {
        let loaded = try await MeshInstance.loadAsync(
          path: "Actors/capsule",
          onSceneProgress: { _ in },
          onTextureProgress: { _, _, _ in }
        )
        await MainActor.run {
          self.capsuleMeshInstances = loaded
        }
      } catch {
        logger.error("Failed to load capsule mesh: \(error)")
      }
    }
  }

  /// Calculate world transform for a node by traversing up the hierarchy
  private func calculateNodeWorldTransform(_ node: Node, scene: Scene) -> mat4 {
    var transform = convertAssimpMatrix(node.transformation)
    var currentNode = node.assimpNode

    while let parent = currentNode.parent {
      let parentTransform = convertAssimpMatrix(parent.transformation)
      transform = parentTransform * transform
      currentNode = parent
    }

    return transform
  }

  /// Convert Assimp matrix to GLMath mat4
  /// Assimp stores matrices in row-major order (a1-a4 is first row)
  private func convertAssimpMatrix(_ matrix: Assimp.Matrix4x4) -> mat4 {
    let row1 = vec4(Float(matrix.a1), Float(matrix.b1), Float(matrix.c1), Float(matrix.d1))
    let row2 = vec4(Float(matrix.a2), Float(matrix.b2), Float(matrix.c2), Float(matrix.d2))
    let row3 = vec4(Float(matrix.a3), Float(matrix.b3), Float(matrix.c3), Float(matrix.d3))
    let row4 = vec4(Float(matrix.a4), Float(matrix.b4), Float(matrix.c4), Float(matrix.d4))
    return mat4(row1, row2, row3, row4)
  }

  func update(window: Window, deltaTime: Float) {
    if showingPickupView {
      // Update pickup view
      pickupView?.update(window: window, deltaTime: deltaTime)
    } else if showingMainMenu {
      // Update main menu
      mainMenu.update(window: window, deltaTime: deltaTime)
    } else {
      // Only handle movement if dialog is not active and input is enabled
      if !dialogView.isActive && Input.player1.isEnabled {
        // Handle WASD movement
        handleMovement(window.keyboard, deltaTime)

        // Handle weapon system hold mode and firing
        // Update weapon system (for rate of fire timing)
        weaponSystem.update(deltaTime: deltaTime)

        // Handle hold mode for Space
        if !weaponSystem.usesToggledAiming {
          if window.keyboard.state(of: .space) == .pressed {
            // Space is held - enter ready aim, then aim
            if weaponSystem.currentAimState == .idle {
              weaponSystem.enterReadyAim()
            } else if weaponSystem.currentAimState == .readyAim {
              weaponSystem.enterAim()
            }
          } else {
            // Space released - exit aim
            if weaponSystem.currentAimState != .idle {
              weaponSystem.exitAim()
            }
          }
        }

        // Handle firing with Ctrl (hold to fire)
        if window.keyboard.state(of: .leftControl) == .pressed || window.keyboard.state(of: .rightControl) == .pressed {
          if weaponSystem.isAiming {
            _ = weaponSystem.fire()
          }
        }
      }

      // Update prerendered environment animation
      prerenderedEnvironment?.update()
    }

    // Update dialog view
    dialogView.update(deltaTime: deltaTime)

    // Update FPS (EMA)
    if deltaTime > 0 {
      let inst = 1.0 / deltaTime
      smoothedFPS = smoothedFPS * 0.9 + inst * 0.1
    }
  }

  // MARK: Input

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      // Forward input to pickup view
      pickupView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    if showingMainMenu {
      // Handle escape key with nested view support
      if key == .escape {
        // If there's a nested view (item/document), let MainMenu handle it first
        if mainMenu.hasNestedViewOpen {
          // Forward to main menu, which will forward to the nested view
          mainMenu.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
          return
        }
        // No nested view, close the main menu
        UISound.select()
        hideMainMenu()
        return
      }

      // Handle I, M, and Tab to close main menu (always close, no nested check)
      if key == .i || key == .m || key == .tab {
        UISound.select()
        hideMainMenu()
        return
      }

      // Forward other input to main menu
      mainMenu.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    } else {
      // Handle dialog advancement keys first (these always work)
      switch key {
      case .f, .enter, .numpadEnter:
        // Handle interaction - either advance dialog or interact with action
        // Dialog advancement keys always work, even when dialog is active
        if dialogView.isActive {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk
            //UISound.select()
          } else if dialogView.isFinished {
            // Dialog finished, dismiss it (disables input synchronously)
            dialogView.dismiss()
          }
        } else {
          // No dialog showing, handle interaction with detected action
          handleInteraction()
        }
        return

      case .space:
        // Handle aim mode (Space) - toggle mode only
        if dialogView.isActive {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk
          } else if dialogView.isFinished {
            dialogView.dismiss()
          }
        } else {
          // Handle aim mode toggle
          if weaponSystem.usesToggledAiming {
            weaponSystem.toggleAim()
          } else {
            // Hold mode - enter ready aim on press
            weaponSystem.enterReadyAim()
          }
        }
        return

      default:
        break
      }

      // Skip other gameplay keys if dialog is active and not finished
      guard !dialogView.isActive else { return }

      // Handle other gameplay keys
      switch key {
      case .tab, .i:
        UISound.select()
        showMainMenu(tab: .inventory)

      case .m:
        UISound.select()
        showMainMenu(tab: .map)

      case .escape:
        // Exit debug camera override mode if active
        if isDebugCameraOverrideMode {
          UISound.select()
          isDebugCameraOverrideMode = false
        }
        break

      case .semicolon:
        UISound.select()
        // Enter debug camera override mode when manually cycling cameras
        isDebugCameraOverrideMode = true
        prerenderedEnvironment?.cycleToNextCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .apostrophe:
        UISound.select()
        // Enter debug camera override mode when manually cycling cameras
        isDebugCameraOverrideMode = true
        prerenderedEnvironment?.cycleToPreviousCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .graveAccent:
        UISound.select()
        // Enter debug camera override mode and switch to debug camera
        isDebugCameraOverrideMode = true
        prerenderedEnvironment?.switchToDebugCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .r:
        UISound.select()
        // Reset player to spawn
        playerPosition = spawnPosition
        playerRotation = spawnRotation
        previousPlayerPosition = spawnPosition  // Reset footstep tracking
        footstepAccumulatedDistance = 0.0  // Reset footstep accumulator

        // Also reset character controller if it exists
        if let characterController {
          characterController.position = RVec3(x: spawnPosition.x, y: spawnPosition.y, z: spawnPosition.z)
          let rotationQuat = Quat(x: 0, y: sin(spawnRotation / 2), z: 0, w: cos(spawnRotation / 2))
          characterController.rotation = rotationQuat
          characterController.linearVelocity = Vec3(x: 0, y: 0, z: 0)  // Stop all movement
        }

      case .l:
        UISound.select()
        // Toggle mist visualization
        if let env = prerenderedEnvironment {
          env.showMist.toggle()
          logger.trace("🌫️ Debug: Mist visualization = \(env.showMist ? "ON" : "OFF")")
        }

      case .u:
        UISound.select()
        visualizePhysics.toggle()
        logger.trace("Debug renderer: \(visualizePhysics ? "ON" : "OFF")")

      case .leftControl, .rightControl:
        // Fire weapon (Ctrl)
        guard weaponSystem.isAiming else { break }
        _ = weaponSystem.fire()
        break

      default:
        break
      }
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      pickupView?.onMouseMove(window: window, x: x, y: y)
    } else if showingMainMenu {
      mainMenu.onMouseMove(window: window, x: x, y: y)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      pickupView?.onMouseButton(window: window, button: button, state: state, mods: mods)
    } else if showingMainMenu {
      mainMenu.onMouseButton(window: window, button: button, state: state, mods: mods)
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      pickupView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if showingMainMenu {
      // Handle right-click with nested view support (same as Escape)
      if button == .right {
        // If there's a nested view (item/document), let MainMenu handle it first
        if mainMenu.hasNestedViewOpen {
          // Forward to main menu, which will forward to the nested view
          mainMenu.onMouseButtonPressed(window: window, button: button, mods: mods)
          return
        }
        // No nested view, close the main menu
        UISound.select()
        hideMainMenu()
        return
      }

      // Forward other mouse input to main menu
      mainMenu.onMouseButtonPressed(window: window, button: button, mods: mods)
    } else {
      // Handle interaction - either advance dialog or interact with action
      // Dialog advancement always works, even when dialog is active
      if button == .left {
        if dialogView.isActive {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk
            UISound.select()
          } else if dialogView.isFinished {
            // Dialog finished, dismiss it (disables input synchronously)
            dialogView.dismiss()
            UISound.select()
          }
        } else {
          // No dialog showing, handle interaction with detected action
          handleInteraction()
        }
      }
    }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      // No-op for pickup view
    } else if showingMainMenu {
      mainMenu.onMouseButtonReleased(window: window, button: button, mods: mods)
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      pickupView?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    } else if showingMainMenu {
      mainMenu.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    }
  }

  private func showMainMenu(tab: MainMenuTabs.Tab) {
    mainMenu.setActiveTab(tab, animated: false)
    showingMainMenu = true
  }

  private func hideMainMenu() {
    showingMainMenu = false
  }

  private var pickupViewContinuation: CheckedContinuation<Bool, Never>?

  func showPickupView(item: Item, quantity: Int = 1) async -> Bool {
    // Fade to black
    await ScreenFade.shared.fadeToBlack(duration: 0.3)

    // Show view (create and attach)
    pickupView = PickupView(item: item, quantity: quantity)

    // Set up callbacks
    pickupView?.onItemPlaced = { [weak self] slotIndex, placedItem, placedQuantity in
      guard let self = self else { return }
      // Update inventory directly
      if slotIndex < Inventory.player1.slots.count {
        Inventory.player1.slots[slotIndex] = ItemSlotData(
          item: placedItem, quantity: placedQuantity > 1 ? placedQuantity : nil)
      }
      // Resume continuation with success
      self.pickupViewContinuation?.resume(returning: true)
      self.pickupViewContinuation = nil
      // Close pickup view with fade
      Task { await self.hidePickupView() }
    }

    pickupView?.onCancel = { [weak self] in
      guard let self = self else { return }
      // Resume continuation with failure (cancelled)
      self.pickupViewContinuation?.resume(returning: false)
      self.pickupViewContinuation = nil
      // Close pickup view with fade
      Task { await self.hidePickupView() }
    }

    // Attach window
    pickupView?.onAttach(window: Engine.shared.window)

    showingPickupView = true

    // Fade back in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Play gong sound when showing pickup view
    UISound.woosh()

    // After fade completes, start slide-in animation
    pickupView?.startSlideInAnimation()

    // Wait for continuation to complete
    return await withCheckedContinuation { continuation in
      self.pickupViewContinuation = continuation
    }
  }

  private func hidePickupView() async {
    // Fade to black
    await ScreenFade.shared.fadeToBlack(duration: 0.3)

    // Hide view
    showingPickupView = false
    pickupView = nil

    // Fade back in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Re-enable input after fade completes
    Input.player1.isEnabled = true
  }

  private func loadSceneScript() {
    guard scene != nil else {
      logger.error("⚠️ No scene to load script for")
      return
    }

    // Convert scene name to class name (e.g., "radar_office" -> "RadarOffice", "test" -> "Test")
    let className = sceneNameToClassName(sceneName)

    // Try to load the class using ScriptRegistry
    guard let script = ScriptRegistry.shared.create(className) else {
      logger.error("⚠️ Could not load scene script class: \(className)")
      logger.error("⚠️ Registered classes: \(ScriptRegistry.shared.allRegisteredClasses())")
      return
    }

    sceneScript = script
    logger.trace("✅ Loaded scene script: \(className)")

    // Call sceneDidLoad() after initialization
    sceneScript?.sceneDidLoad()
  }

  /// Convert scene name to class name
  /// Examples: "test" -> "Test", "radar_office" -> "RadarOffice"
  private func sceneNameToClassName(_ sceneName: String) -> String {
    // Split by underscores and capitalize first letter of each word
    let components = sceneName.split(separator: "_")
    let capitalized = components.map { word in
      word.isEmpty ? "" : word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
    return capitalized.joined()
  }

  /// Position player at an entry node
  /// - Parameters:
  ///   - entryName: The entry name (e.g., "Entry_1", "hallway" will look for "Entry_hallway")
  ///   - scene: The scene to search for the entry in
  private func positionPlayerAtEntry(_ entryName: String, in scene: Scene) {
    // Try to find entry with exact name first, then try with "Entry_" prefix
    let entryNodeName: String
    if entryName.hasPrefix("Entry_") {
      entryNodeName = entryName
    } else {
      entryNodeName = "Entry_\(entryName)"
    }

    guard let entryNode = scene.rootNode.findNode(named: entryNodeName) else {
      logger.warning("⚠️ Entry node not found: \(entryNodeName)")
      return
    }

    let entryWorld = calculateNodeWorldTransform(entryNode, scene: scene)
    let extractedPos = vec3(entryWorld[3].x, entryWorld[3].y, entryWorld[3].z)
    let fwd = vec3(entryWorld[2].x, entryWorld[2].y, entryWorld[2].z)
    let yaw = atan2(fwd.x, fwd.z)
    let entryRotation = yaw - (.pi * 0.5)

    // The entry position is at the feet, but character controller uses center position
    // Adjust Y position to account for capsule half-height
    let capsuleHalfHeight: Float = 0.8
    let adjustedPos = vec3(extractedPos.x, extractedPos.y + capsuleHalfHeight, extractedPos.z)

    // Update player position and rotation
    playerPosition = adjustedPos
    playerRotation = entryRotation
    spawnPosition = extractedPos  // Keep spawn position at feet for reference
    spawnRotation = entryRotation
    previousPlayerPosition = adjustedPos  // Reset footstep tracking
    footstepAccumulatedDistance = 0.0  // Reset footstep accumulator

    // Update character controller if it exists
    if let characterController {
      characterController.position = RVec3(x: adjustedPos.x, y: adjustedPos.y, z: adjustedPos.z)
      let rotationQuat = Quat(x: 0, y: sin(entryRotation / 2), z: 0, w: cos(entryRotation / 2))
      characterController.rotation = rotationQuat
      characterController.linearVelocity = Vec3(x: 0, y: 0, z: 0)  // Stop all movement
    }

    logger.trace("🚀 Positioned player at \(entryNodeName): \(extractedPos)")
  }

  /// Transition to a different entry in the current scene
  /// - Parameter entry: The entry name (e.g., "hallway", "Entry_2")
  @MainActor func transition(to entry: String) async {
    guard let currentScene = scene else {
      logger.warning("⚠️ Cannot transition: no current scene")
      return
    }

    // Play door open sound before fading out
    UISound.doorOpenA()

    // Fade out
    await ScreenFade.shared.fadeToBlack(duration: 0.3)

    // Position player at entry
    positionPlayerAtEntry(entry, in: currentScene)

    // Try to switch camera based on convention:
    // - Named areas (like "hallway"): try "Camera_hallway_1", fall back to "Camera_1"
    // - Unnamed areas (like "Entry_1"): try "Camera_1"
    let cameraName: String
    let prerenderedCameraName: String
    if entry.hasPrefix("Entry_") {
      // Unnamed area - just use Camera_1
      cameraName = "Camera_1"
      // For prerendered environment, Entry_1 -> "1", Entry_2 -> "2", etc.
      let entrySuffix = String(entry.dropFirst(6))  // Remove "Entry_" prefix
      prerenderedCameraName = entrySuffix
    } else {
      // Named area - try "Camera_{area}_1", fall back to "Camera_1"
      let areaCameraName = "Camera_\(entry)_1"
      if currentScene.rootNode.findNode(named: areaCameraName) != nil {
        cameraName = areaCameraName
        // For prerendered environment, "hallway" -> "hallway_1"
        prerenderedCameraName = "\(entry)_1"
      } else {
        cameraName = "Camera_1"
        prerenderedCameraName = "1"
      }
    }

    // Switch 3D camera
    syncActiveCamera(name: cameraName)

    // Switch prerendered environment camera
    try? prerenderedEnvironment?.switchToCamera(prerenderedCameraName)
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? prerenderedCameraName

    // Update current area in scene script
    sceneScript?.currentArea = entry

    await Task.sleep(0.15)

    // Fade in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Play door close sound after fading in
    UISound.doorCloseA()
  }

  /// Transition to a different scene
  /// - Parameters:
  ///   - scene: The scene name to load
  ///   - entry: Optional entry name (defaults to "Entry_1" if not specified)
  @MainActor func transition(toScene scene: String, entry: String? = nil) async {
    // Play door open sound before fading out
    UISound.doorOpenA()

    // Fade out
    await ScreenFade.shared.fadeToBlack(duration: 0.3)

    // Load the new scene and position at entry (defaults to Entry_1 if not specified)
    let entryName = entry ?? "Entry_1"

    // Determine prerendered camera name based on entry (same logic as transition(to:))
    // We need to determine this before loading the scene, but we'll need the scene to check for named cameras
    // So we'll load with a default and update if needed
    let defaultPrerenderedCameraName: String
    if entryName.hasPrefix("Entry_") {
      // Unnamed area - Entry_1 -> "1", Entry_2 -> "2", etc.
      let entrySuffix = String(entryName.dropFirst(6))  // Remove "Entry_" prefix
      defaultPrerenderedCameraName = entrySuffix
    } else {
      // For named areas, we'll default to "1" and update after scene loads if needed
      defaultPrerenderedCameraName = "1"
    }

    // Load the scene
    await loadScene(scene, entry: entryName, prerenderedCameraName: defaultPrerenderedCameraName)

    // If it's a named area, check if we need to update the camera
    if !entryName.hasPrefix("Entry_"), let currentScene = self.scene {
      let areaCameraName = "Camera_\(entryName)_1"
      if currentScene.rootNode.findNode(named: areaCameraName) != nil {
        let prerenderedCameraName = "\(entryName)_1"
        try? prerenderedEnvironment?.switchToCamera(prerenderedCameraName)
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? prerenderedCameraName
      }
    }

    await Task.sleep(0.15)

    // Fade in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Play door close sound after fading in
    UISound.doorCloseA()
  }

  /// Clear all physics bodies from the previous scene
  private func clearOldPhysicsBodies() {
    let bodyInterface = physicsSystem.bodyInterface()

    // Remove old character controller
    characterController = nil
    capsuleSensorBodyID = nil

    // Remove all collision bodies
    for bodyID in collisionBodyIDs {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    collisionBodyIDs.removeAll()

    // Remove all action bodies
    for bodyID in actionBodyNames.keys {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    actionBodyNames.removeAll()

    // Remove all trigger bodies
    for bodyID in triggerBodyNames.keys {
      bodyInterface.removeAndDestroyBody(bodyID)
    }
    triggerBodyNames.removeAll()
  }

  /// Load a scene by name, setting up everything (scene, physics, prerendered environment, player position)
  /// - Parameters:
  ///   - sceneName: The scene name to load
  ///   - entry: The entry name to position player at (defaults to "Entry_1")
  ///   - prerenderedCameraName: Optional camera name for prerendered environment (defaults to "1")
  @MainActor func loadScene(_ sceneName: String, entry: String = "Entry_1", prerenderedCameraName: String? = nil) async
  {
    do {
      // Update scene name
      self.sceneName = sceneName

      // Load the scene file
      let scenePath = Bundle.game.path(forResource: "Scenes/\(sceneName)", ofType: "glb")!
      let assimpScene = try Assimp.Scene(
        file: scenePath,
        flags: [.triangulate, .flipUVs, .calcTangentSpace]
      )

      // Wrap in our Scene wrapper
      let scene = Scene(assimpScene)

      print("\(scene.rootNode)")
      //scene.cameras.forEach { logger.trace("\($0)") }

      // Set the scene
      self.scene = scene

//      // Clear old physics bodies if physics system is ready
//      guard let physicsSystem = physicsSystem else {
//        logger.error("⚠️ Physics system not ready, cannot load physics for scene '\(sceneName)'")
//        return
//      }

      logger.trace("🔄 Loading physics for scene '\(sceneName)'...")
      clearOldPhysicsBodies()

      // Load new collision bodies
      loadCollisionBodiesIntoPhysics(scene: scene)
      loadActionBodiesIntoPhysics(scene: scene)
      loadTriggerBodiesIntoPhysics(scene: scene)
      physicsSystem.optimizeBroadPhase()
      logger.trace(
        "✅ Loaded physics bodies: \(collisionBodyIDs.count) collision, \(actionBodyNames.count) action, \(triggerBodyNames.count) trigger"
      )

      // Position player at entry (updates player position/rotation)
      // This already adjusts for capsule height, so playerPosition is the center position
      positionPlayerAtEntry(entry, in: scene)

      // Create character controller at the positioned location
      // Use the position that was set by positionPlayerAtEntry (already adjusted for capsule height)
      createCharacterController(at: playerPosition, rotation: playerRotation, in: physicsSystem)

      if characterController == nil {
        logger.error("⚠️ Failed to create character controller at entry '\(entry)'")
      } else {
        logger.trace("✅ Character controller created successfully")
      }

      // Mark physics system as ready for updates
      physicsSystemReady = true

      // Load scene script class dynamically
      loadSceneScript()

      // Set initial area
      sceneScript?.currentArea = entry

      // Initialize active camera from scene using default name Camera_1
      syncActiveCamera(name: "Camera_1")

      // Load foreground meshes (nodes with -fg suffix)
      loadForegroundMeshes(scene: scene)

      // Initialize prerendered environment for the scene
      let cameraName = prerenderedCameraName ?? "1"
      do {
        prerenderedEnvironment = try PrerenderedEnvironment(sceneName, cameraName: cameraName)
        // Sync the selectedCamera property with the actual current camera
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? cameraName
      } catch {
        logger.error("⚠️ Failed to initialize PrerenderedEnvironment for scene '\(sceneName)': \(error)")
      }

      // Disable small-room clamping for real scene navigation
      restrictMovementToRoom = false
    } catch {
      logger.error("⚠️ Failed to load scene '\(sceneName)': \(error)")
    }
  }

  private func handleInteraction() {
    guard let detectedActionName else { return }
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

  private func handleCameraTrigger(cameraName: String) {
    // Ignore camera triggers when in debug camera override mode
    if isDebugCameraOverrideMode {
      logger.trace("📷 Camera trigger '\(cameraName)' ignored: debug camera override mode is active")
      return
    }

    // Extract area from camera name
    // Examples: "hallway_1" -> "hallway", "Entry_1" -> "Entry_1"
    let triggerArea: String
    if cameraName.hasPrefix("Entry_") {
      // Entry areas keep the full name (e.g., "Entry_1")
      triggerArea = cameraName
    } else {
      // Named areas: remove trailing "_1", "_2", etc. (e.g., "hallway_1" -> "hallway")
      if let lastUnderscoreIndex = cameraName.lastIndex(of: "_") {
        let beforeUnderscore = String(cameraName[..<lastUnderscoreIndex])
        // Check if after underscore is just a number
        let afterUnderscore = String(cameraName[cameraName.index(after: lastUnderscoreIndex)...])
        if afterUnderscore.allSatisfy({ $0.isNumber }) {
          triggerArea = beforeUnderscore
        } else {
          // Not a numbered camera, use full name
          triggerArea = cameraName
        }
      } else {
        // No underscore, use full name
        triggerArea = cameraName
      }
    }

    // Check if player is in the correct area
    let currentArea = sceneScript?.currentArea
//    if currentArea == nil {
//      sceneScript?.currentArea = triggerArea
//    } else
    if let currentArea, currentArea != triggerArea {
      logger.trace(
        "📷 Camera trigger '\(cameraName)' ignored: player is in area '\(currentArea)', trigger requires '\(triggerArea)'"
      )
      return
    }

    // Switch 3D camera (e.g., "hallway_1" -> "Camera_hallway_1")
    let cameraNodeName = "Camera_\(cameraName)"
    syncActiveCamera(name: cameraNodeName)

    // Switch prerendered environment camera (e.g., "hallway_1" -> "hallway_1")
    try? prerenderedEnvironment?.switchToCamera(cameraName)
    selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? cameraName

    logger.trace("📷 Camera trigger activated: switched to camera '\(cameraName)' (area: '\(triggerArea)')")
  }

  private func callTriggerMethod(triggerName: String) {
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

  private func createCharacterController(at position: vec3, rotation: Float, in system: PhysicsSystem) {
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
      in: system
    )

    // Set mass and strength
    characterController?.mass = 70.0  // kg
    characterController?.maxStrength = 500.0  // N

    // Initialize footstep tracking position
    previousPlayerPosition = position

    // Create a sensor sphere in front of the capsule for detecting action triggers
    createCapsuleSensor(at: position, in: system)

    logger.trace("✅ Created character controller at position (\(position.x), \(position.y), \(position.z))")
  }

  private func createCapsuleSensor(at position: vec3, in system: PhysicsSystem) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Create a small sphere sensor in front of the capsule
    // Position it slightly in front and at the same height as the capsule
    let sensorRadius: Float = 0.5
    let sensorDistance: Float = 1.2  // Distance in front of capsule
    let sensorShape = SphereShape(radius: sensorRadius)

    // Position sensor in front of capsule (using forward direction)
    let forwardX = GLMath.sin(spawnRotation)
    let forwardZ = GLMath.cos(spawnRotation)
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

  private func handleMovement(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Tank controls: A/D rotate, W/S move forward/backward
    let rotationDelta = rotationSpeed * deltaTime

    // Always allow rotation, even while aiming
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      playerRotation += rotationDelta
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      playerRotation -= rotationDelta
    }

    // Don't allow forward/backward movement while aiming
    if weaponSystem.isAiming { return }

    // Calculate forward direction from rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Update character controller if it exists
    if let characterController {
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
        currentVelocity.y = currentYVelocity + physicsSystem.getGravity().y * deltaTime
      } else {
        currentVelocity.y = 0  // On ground, no vertical velocity
      }

      characterController.linearVelocity = currentVelocity

      // Update character rotation
      let rotationQuat = Quat(x: 0, y: sin(playerRotation / 2), z: 0, w: cos(playerRotation / 2))
      characterController.rotation = rotationQuat

      // Only update character controller and physics system if ready
      if physicsSystemReady {
        // Update physics system FIRST (jobSystem is required)
        // This internally waits for all jobs to complete, so it's synchronous
        // This ensures the physics world is in a consistent state before character controller updates
          physicsSystem.update(deltaTime: deltaTime, collisionSteps: 1, jobSystem: jobSystem)

        // Update character controller (this does the physics movement)
        let characterLayer: ObjectLayer = 2  // Dynamic layer
        characterController.update(deltaTime: deltaTime, layer: characterLayer, in: physicsSystem)

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
        playerPosition = newPosition
      }

      // FIX 3: Cache collision queries - only run every N frames
      queryFrameCounter += 1
      let shouldUpdateQueries = (queryFrameCounter % queryCacheInterval) == 0

      // Check for action body contacts (sensor bodies)
      detectedActionName = nil

      // Also check character controller contacts (always check these, they're fast)
      let contacts = characterController.activeContacts()
      for contact in contacts {
        if contact.isSensorB, let actionName = actionBodyNames[contact.bodyID] {
          detectedActionName = actionName.replacing(/-action$/, with: "")
          break  // Just show first detected action
        }
      }

      // Update capsule sensor position to follow the capsule in front
      // And check for action body overlaps using collision query
      if let sensorBodyID = capsuleSensorBodyID {
        let bodyInterface = physicsSystem.bodyInterface()

        // Calculate position in front of capsule based on current rotation
        let forwardX = GLMath.sin(playerRotation)
        let forwardZ = GLMath.cos(playerRotation)
        let sensorDistance: Float = 1.2
        let sensorOffset = vec3(forwardX * sensorDistance, 0, forwardZ * sensorDistance)
        let sensorPosition = playerPosition + sensorOffset

        // Update sensor position using Body wrapper
        var sensorBody = bodyInterface.body(sensorBodyID, in: physicsSystem)
        sensorBody.position = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)

        // FIX 3: Only query for overlapping action bodies every N frames
        if shouldUpdateQueries {
          let sensorShape = SphereShape(radius: 0.5)
          var baseOffset = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)
          cachedActionQueryResults = physicsSystem.collideShapeAll(
            shape: sensorShape,
            scale: Vec3(x: 1, y: 1, z: 1),
            baseOffset: &baseOffset
          )
        }

        // Check if any of the colliding bodies are action bodies (use cached results)
        for result in cachedActionQueryResults {
          let bodyID = result.bodyID2
          if let actionName = actionBodyNames[bodyID] {
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
        if contact.isSensorB, let triggerName = triggerBodyNames[contact.bodyID] {
          // Handle camera triggers
          if triggerName.hasPrefix("CameraTrigger_") {
            let cameraName = String(triggerName.dropFirst("CameraTrigger_".count))
            currentCameraTriggers.append(cameraName)
            // Check if we're not already on this camera - switch if needed
            let currentCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
            if currentCamera != cameraName {
              handleCameraTrigger(cameraName: cameraName)
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
        cachedTriggerQueryResults = physicsSystem.collideShapeAll(
          shape: triggerCheckShape,
          scale: Vec3(x: 1, y: 1, z: 1),
          baseOffset: &playerBaseOffset
        )
      }

      // Check for trigger bodies (use cached results)
      for result in cachedTriggerQueryResults {
        let bodyID = result.bodyID2
        if let triggerName = triggerBodyNames[bodyID] {
          // Handle camera triggers
          if triggerName.hasPrefix("CameraTrigger_") {
            let cameraName = String(triggerName.dropFirst("CameraTrigger_".count))
            currentCameraTriggers.append(cameraName)
            // Check if we're not already on this camera - switch if needed
            let currentCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
            if currentCamera != cameraName {
              handleCameraTrigger(cameraName: cameraName)
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
        callTriggerMethod(triggerName: triggerName)
      }

      // Update previous triggers for next frame
      previousTriggers = newTriggers
    }
  }

  func draw() {
    if showingPickupView {
      // Draw pickup view
      pickupView?.draw()
    } else if showingMainMenu {
      // Draw main menu
      mainMenu.draw()
    } else {
      // Set up 3D rendering
      let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)

      // Use Camera_1 projection if available, otherwise fallback to default
      let projection: mat4
      if let camera {
        // Check if camera is orthographic (FOV is 0 or orthographicWidth is set)
        let isOrthographic = camera.horizontalFOV == 0.0 || camera.orthographicWidth > 0.0

        if isOrthographic {
          // Orthographic camera: use orthographicWidth (half width) and aspect ratio
          let orthoWidth = camera.orthographicWidth > 0.0 ? camera.orthographicWidth : 1.0

          // IMPORTANT: Use camera's stored aspect ratio if available, otherwise viewport aspect
          let finalAspect: Float
          if camera.aspect > 0 {
            finalAspect = camera.aspect
          } else {
            finalAspect = aspectRatio
          }

          // Calculate orthographic bounds
          // orthographicWidth is half the horizontal width
          let left = -orthoWidth
          let right = orthoWidth
          // Height = width / aspect, so halfHeight = orthoWidth / aspect
          let bottom = -orthoWidth / finalAspect
          let top = orthoWidth / finalAspect

          projection = GLMath.ortho(left, right, bottom, top, camera.clipPlaneNear, camera.clipPlaneFar)

          logger.trace(
            "📐 Using orthographic camera: width=\(orthoWidth * 2), aspect=\(finalAspect), near=\(camera.clipPlaneNear), far=\(camera.clipPlaneFar)"
          )
        } else {
          // Perspective camera: use existing FOV calculation
          // IMPORTANT: Use camera's stored aspect ratio if available, otherwise viewport aspect
          // The prerendered images were rendered with a specific aspect ratio, so we should match it
          let finalAspect: Float
          if camera.aspect > 0 {
            // Use camera's aspect ratio (this is what the prerendered images were rendered with)
            finalAspect = camera.aspect
          } else {
            // Fallback to viewport aspect ratio
            finalAspect = aspectRatio
          }

          // Convert horizontal FOV to vertical FOV
          // GLMath.perspective expects vertical FOV (fovy), but Assimp gives us horizontal FOV
          // Formula: verticalFOV = 2 * atan(tan(horizontalFOV / 2) / aspectRatio)
          let horizontalFOVHalf = camera.horizontalFOV / 2.0
          let verticalFOV = 2.0 * atan(tan(horizontalFOVHalf) / finalAspect)

          projection = GLMath.perspective(verticalFOV, finalAspect, camera.clipPlaneNear, camera.clipPlaneFar)

          // Debug: Print aspect ratio mismatch if significant
          if abs(finalAspect - aspectRatio) > 0.01 {
            logger.warning("⚠️ Aspect ratio mismatch: camera=\(finalAspect), viewport=\(aspectRatio)")
          }
        }
      } else {
        projection = GLMath.perspective(45.0, aspectRatio, 0.1, 100.0)
      }

      GraphicsContext.current?.renderer.withUIContext {
        // Render prerendered environment first (as background)
        prerenderedEnvironment?.render(projectionMatrix: projection)

        // Clear depth buffer after rendering if debug flag is set
        if disableDepth {
          glClear(GL_DEPTH_BUFFER_BIT)
        }
      }

      // Get view matrix from camera node's world transform
      // In glTF/Assimp, the camera node's transform IS the camera-to-world transform
      // To get the view matrix (world-to-camera), we simply invert it
      var view: mat4
      let cameraWorld: mat4
      // Check if camera world transform is valid (not identity)
      if cameraWorldTransform != mat4(1) {
        cameraWorld = cameraWorldTransform
        // The view matrix is the inverse of the camera's world transform
        // This matches how the prerendered images were rendered
        view = inverse(cameraWorld)
      } else {
        // Fallback: use identity view matrix if camera not available
        cameraWorld = mat4(1)
        view = mat4(1)
      }

      // Apply screen shake offset to view matrix
      let shakeOffset = ScreenShake.shared.offset
      if shakeOffset.x != 0.0 || shakeOffset.y != 0.0 {
        // Translate view matrix by shake offset
        // Convert screen space offset to world space (approximate using viewport size)
        // Scale factor determines how much world space movement corresponds to screen pixels
        let viewportSize = Engine.viewportSize
        let worldOffsetX = shakeOffset.x / viewportSize.width * 10.0  // Scale factor
        let worldOffsetY = shakeOffset.y / viewportSize.height * 10.0  // Scale factor
        view = GLMath.translate(view, vec3(worldOffsetX, worldOffsetY, 0.0))
      }

      // Do not clear depth; we rely on PrerenderedEnvironment writing correct depth

      // Draw capsule mesh
      if !capsuleMeshInstances.isEmpty {
        // Ensure depth testing/writes are enabled for 3D integration
        glEnable(GL_DEPTH_TEST)
        glDepthMask(true)
        glDepthFunc(GL_LEQUAL)

        // Create model matrix: translate to player position, then rotate around Y axis
        // Offset Y downward so capsule sits on floor (assuming origin is at center)
        var adjustedPosition = playerPosition
        adjustedPosition.y -= capsuleHeightOffset
        var modelMatrix = GLMath.translate(mat4(1), adjustedPosition)
        modelMatrix = GLMath.rotate(modelMatrix, playerRotation, vec3(0, 1, 0))

        for meshInstance in capsuleMeshInstances {
          // Combine the mesh's original transform with player transform
          let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix

          // Extract camera position from world transform (4th column)
          let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)

          // Get lighting from scene lights
          let lighting = getSceneLighting()

          meshInstance.draw(
            projection: projection,
            view: view,
            modelMatrix: combinedModelMatrix,
            cameraPosition: cameraPosition,
            lightDirection: lighting.mainLight.direction,
            lightColor: lighting.mainLight.color,
            lightIntensity: lighting.mainLight.intensity,
            fillLightDirection: lighting.fillLight.direction,
            fillLightColor: lighting.fillLight.color,
            fillLightIntensity: lighting.fillLight.intensity,
            diffuseOnly: false
          )
        }
      }

      // Draw foreground meshes (nodes with -fg suffix)
      if !foregroundMeshInstances.isEmpty {
        glEnable(GL_DEPTH_TEST)
        glDepthMask(true)
        glDepthFunc(GL_LEQUAL)

        let lighting = getSceneLighting()
        let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)

        for meshInstance in foregroundMeshInstances {
          // Skip if not visible (node is hidden)
          guard meshInstance.isVisible() else { continue }

          meshInstance.draw(
            projection: projection,
            view: view,
            modelMatrix: meshInstance.transformMatrix,
            cameraPosition: cameraPosition,
            lightDirection: lighting.mainLight.direction,
            lightColor: lighting.mainLight.color,
            lightIntensity: lighting.mainLight.intensity,
            fillLightDirection: lighting.fillLight.direction,
            fillLightColor: lighting.fillLight.color,
            fillLightIntensity: lighting.fillLight.intensity,
            diffuseOnly: false
          )
        }
      }

      // Always call nextFrame to maintain consistent timing (even when not visualizing)
      // This might help with synchronization/timing issues
      if let debugRenderer {
        debugRenderer.nextFrame()
      }

      // Update debug renderer camera and draw if enabled
      if let debugRenderer {
        currentProjection = projection
        currentView = view

        // Set camera position for debug renderer (extract from view matrix)
        let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)
        debugRenderer.setCameraPosition(RVec3(x: cameraPosition.x, y: cameraPosition.y, z: cameraPosition.z))

        if visualizePhysics {
          debugRenderer.drawMarker(RVec3(x: 0, y: 0, z: 0), color: 0xFFFF00FF, size: 2.0)
          physicsSystem.drawBodies(debugRenderer: debugRenderer)
        }

        // Draw entry arrows using Jolt debug renderer
        if let loadedScene = scene {
          drawEntryArrows(scene: loadedScene, debugRenderer: debugRenderer)
        }
      }

      // Debug overlay (top-left)
      drawDebugInfo()

      // Draw dialog view (on top of everything)
      GraphicsContext.current?.renderer.withUIContext {
        dialogView.draw()
      }
    }
  }

  private func drawDebugInfo() {
    // Show "(override)" suffix when in debug camera override mode
    let cameraDisplayName = isDebugCameraOverrideMode ? "\(selectedCamera) (override)" : selectedCamera

    var overlayLines = [
      //String(format: "FPS: %.0f", smoothedFPS),
      //"Scene: \(sceneName)",
      "Camera: \(cameraDisplayName)",

      String(
        format: "Position: %.2f, %.2f, %.2f",
        playerPosition.x,
        playerPosition.y,
        playerPosition.z
      ),

      String(
        format: "Rotation: %.0f° (%.2f rad)",
        playerRotation * 180.0 / .pi,
        playerRotation
      ),

      detectedActionName != nil
        ? "Actions: \(detectedActionName!.prefix(1).lowercased() + detectedActionName!.dropFirst())" : "Actions: none",

      currentTriggers.isEmpty
        ? "Triggers: none"
        : "Triggers: \(currentTriggers.map { $0.prefix(1).lowercased() + $0.dropFirst() }.joined(separator: ", "))",
    ]

    // Add camera triggers line if there are any
    if !currentCameraTriggers.isEmpty {
      overlayLines.append(
        "Camera Triggers: \(currentCameraTriggers.map { $0.prefix(1).lowercased() + $0.dropFirst() }.joined(separator: ", "))"
      )
    }

    let overlay = overlayLines.joined(separator: "\n")

    overlay.draw(
      at: Point(20, Engine.viewportSize.height - 20),
      style: .itemDescription.withMonospacedDigits(true),
      anchor: .topLeft
    )
  }

  private func createGroundPlane() {
    let bodyInterface = physicsSystem.bodyInterface()

    // Use a large BoxShape instead of PlaneShape for better reliability
    // PlaneShape can have issues with collision detection when the character moves away from the origin
    // A large flat box is more reliable and still very efficient
    let groundHalfExtent = Vec3(x: 500.0, y: 0.5, z: 500.0)  // Very large flat box
    let groundShape = BoxShape(halfExtent: groundHalfExtent)

    // Position at y = -0.5 so top surface is at y = 0
    let groundPosition = RVec3(x: 0, y: -0.5, z: 0)
    let groundRotation = Quat.identity

    // Create body settings
    let groundLayer: ObjectLayer = 1  // Static layer
    let bodySettings = BodyCreationSettings(
      shape: groundShape,
      position: groundPosition,
      rotation: groundRotation,
      motionType: .static,
      objectLayer: groundLayer
    )

    // Create and add ground body
    let groundBodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
    if groundBodyID != 0 {
      logger.trace("✅ Created ground plane body ID: \(groundBodyID)")
    } else {
      logger.error("❌ Failed to create ground plane")
    }
  }

  private func loadCollisionBodiesIntoPhysics(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static collision bodies
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-col") {
        let worldTransform = calculateNodeWorldTransform(node, scene: scene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space (includes scale/rotation/translation)
            // We transform to world space because the visual meshes are rendered with world transforms
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

            // Create mesh shape from triangles (already in world space, no body transform needed)
            let meshShape = MeshShape(triangles: triangles)

            // Position is at origin since triangles are already in world space
            let position = vec3(0, 0, 0)

            // Rotation is identity since triangles are already in world space
            let rotation = Quat.identity

            // Create body settings
            let bodySettings = BodyCreationSettings(
              shape: meshShape,
              position: RVec3(x: position.x, y: position.y, z: position.z),
              rotation: rotation,
              motionType: .static,
              objectLayer: staticLayer
            )

            // Create and add body to physics system
            let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
            if bodyID != 0 {
              collisionBodyIDs.append(bodyID)
              logger.trace("✅ Created collision body ID: \(bodyID) for node '\(name)'")
            } else {
              logger.error("❌ Failed to create collision body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func loadActionBodiesIntoPhysics(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static action bodies (same as collision bodies)
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-action") {
        let worldTransform = calculateNodeWorldTransform(node, scene: scene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

            // Create mesh shape from triangles (already in world space)
            let meshShape = MeshShape(triangles: triangles)

            // Position is at origin since triangles are already in world space
            let position = vec3(0, 0, 0)
            let rotation = Quat.identity

            // Create body settings - mark as sensor so it doesn't collide but triggers
            let bodySettings = BodyCreationSettings(
              shape: meshShape,
              position: RVec3(x: position.x, y: position.y, z: position.z),
              rotation: rotation,
              motionType: .static,
              objectLayer: staticLayer
            )
            bodySettings.isSensor = true  // Make it a sensor/trigger

            // Store user data with body ID so we can map it back to name
            // We'll store the name in actionBodyNames after creation

            // Create and add body to physics system
            let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
            if bodyID != 0 {
              // Store mapping from body ID to node name
              actionBodyNames[bodyID] = name
              logger.trace("✅ Created action trigger body ID: \(bodyID) for node '\(name)'")
            } else {
              logger.error("❌ Failed to create action trigger body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func loadTriggerBodiesIntoPhysics(scene: Scene) {
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static trigger bodies (same as collision bodies)
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-trigger") || name.hasPrefix("CameraTrigger_") {
        let worldTransform = calculateNodeWorldTransform(node, scene: scene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Extract triangles from mesh and transform them to world space
            let triangles = extractTrianglesFromMesh(mesh: mesh, transform: worldTransform)

            guard !triangles.isEmpty else { return }

            // Create mesh shape from triangles (already in world space)
            let meshShape = MeshShape(triangles: triangles)

            // Position is at origin since triangles are already in world space
            let position = vec3(0, 0, 0)
            let rotation = Quat.identity

            // Create body settings - mark as sensor so it doesn't collide but triggers
            let bodySettings = BodyCreationSettings(
              shape: meshShape,
              position: RVec3(x: position.x, y: position.y, z: position.z),
              rotation: rotation,
              motionType: .static,
              objectLayer: staticLayer
            )
            bodySettings.isSensor = true  // Make it a sensor/trigger

            // Create and add body to physics system
            let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .dontActivate)
            if bodyID != 0 {
              // Store mapping from body ID to node name
              triggerBodyNames[bodyID] = name
              logger.trace("✅ Created trigger body ID: \(bodyID) for node '\(name)'")
            } else {
              logger.error("❌ Failed to create trigger body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func extractTrianglesFromMesh(mesh: Assimp.Mesh, transform: mat4) -> [Triangle] {
    guard mesh.numberOfVertices > 0, mesh.numberOfFaces > 0 else { return [] }

    let vertices = mesh.vertices
    var triangles: [Triangle] = []

    // Extract faces (triangles) and transform them to world space
    for face in mesh.faces {
      guard face.numberOfIndices == 3 else { continue }  // Only process triangles

      let i1 = Int(face.indices[0])
      let i2 = Int(face.indices[1])
      let i3 = Int(face.indices[2])

      guard i1 < mesh.numberOfVertices, i2 < mesh.numberOfVertices, i3 < mesh.numberOfVertices else {
        continue
      }

      // Get vertex positions in local space
      let v1Local = vec3(
        Float(vertices[i1 * 3 + 0]),
        Float(vertices[i1 * 3 + 1]),
        Float(vertices[i1 * 3 + 2])
      )
      let v2Local = vec3(
        Float(vertices[i2 * 3 + 0]),
        Float(vertices[i2 * 3 + 1]),
        Float(vertices[i2 * 3 + 2])
      )
      let v3Local = vec3(
        Float(vertices[i3 * 3 + 0]),
        Float(vertices[i3 * 3 + 1]),
        Float(vertices[i3 * 3 + 2])
      )

      // Transform to world space (includes scale, rotation, translation)
      let v1World = transform * vec4(v1Local.x, v1Local.y, v1Local.z, 1.0)
      let v2World = transform * vec4(v2Local.x, v2Local.y, v2Local.z, 1.0)
      let v3World = transform * vec4(v3Local.x, v3Local.y, v3Local.z, 1.0)

      triangles.append(
        Triangle(
          v1: Vec3(x: v1World.x, y: v1World.y, z: v1World.z),
          v2: Vec3(x: v2World.x, y: v2World.y, z: v2World.z),
          v3: Vec3(x: v3World.x, y: v3World.y, z: v3World.z),
          materialIndex: 0
        ))
    }

    return triangles
  }

  private func drawEntryArrows(scene: Scene, debugRenderer: DebugRenderer) {
    func traverse(_ node: Node) {
      if let name = node.name, name.hasPrefix("Entry_") {
        let world = calculateNodeWorldTransform(node, scene: scene)
        let origin = vec3(world[3].x, world[3].y, world[3].z)
        // Extract forward direction from Z basis vector
        let forwardZ = vec3(world[2].x, world[2].y, world[2].z)
        // Rotate 90° around Y axis: swap X and Z, negate Z
        // This rotates the forward vector to align with our coordinate system
        let forward = vec3(-forwardZ.z, forwardZ.y, forwardZ.x)

        // Draw arrow using Jolt debug renderer
        let arrowLength: Float = 2.0
        let to = origin + normalize(forward) * arrowLength
        let magentaColor: Jolt.Color = 0xFFFF_00FF  // RGBA: magenta
        debugRenderer.drawArrow(
          from: RVec3(x: origin.x, y: origin.y, z: origin.z),
          to: RVec3(x: to.x, y: to.y, z: to.z),
          color: magentaColor,
          size: 0.5
        )
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }
}
