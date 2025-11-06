import Assimp
import Foundation
import Jolt

@Editable final class MainLoop: RenderLoop {
  // Scene configuration
  private let sceneName: String = "test"
  //  private let sceneName: String = "radar_office"

  // Gameplay state
  private var playerPosition: vec3 = vec3(0, 0, 0)
  private var playerRotation: Float = 0.0
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
  private let capsuleHeightOffset: Float = 1.25

  // Debug renderer for physics visualization
  private var debugRenderer: DebugRenderer?
  private var physicsSystem: PhysicsSystem?
  // Job system for physics updates (required, cannot be null)
  private var jobSystem: JobSystemThreadPool?
  // Store filter objects so they stay alive (PhysicsSystem only keeps references)
  private var broadPhaseLayerInterface: BroadPhaseLayerInterfaceTable?
  private var objectLayerPairFilter: ObjectLayerPairFilterTable?
  private var objectVsBroadPhaseLayerFilter: ObjectVsBroadPhaseLayerFilterTable?
  // Character controller for player capsule
  private var characterController: CharacterVirtual?
  // Mapping from action body IDs to their node names
  private var actionBodyNames: [BodyID: String] = [:]
  // Currently detected action body name (updated each frame)
  private var detectedActionName: String?
  // Mapping from trigger body IDs to their node names
  private var triggerBodyNames: [BodyID: String] = [:]
  // Currently active triggers (OrderedSet to avoid duplicates while maintaining order)
  private var currentTriggers: OrderedSet<String> = []
  // Previous frame's triggers (to detect new entries)
  private var previousTriggers: Set<String> = []
  // Sensor body in front of capsule for detecting action triggers
  private var capsuleSensorBodyID: BodyID?
  // Flag to track if physics system is ready for updates
  private var physicsSystemReady: Bool = false
  var currentProjection: mat4 = mat4(1)  // Accessible by debug renderer implementation
  var currentView: mat4 = mat4(1)  // Accessible by debug renderer implementation

  @Editor var visualizePhysics: Bool = false
  @Editor var disableDepth: Bool = false

  // Scene and camera
  private var scene: Scene?
  private var camera1: Assimp.Camera?
  private var camera1Node: Node?
  private var camera1WorldTransform: mat4 = mat4(1)

  // Scene lights
  private var sceneLights: [(light: Assimp.Light, worldTransform: mat4)] = []

  // Prerendered environment renderer
  private var prerenderedEnvironment: PrerenderedEnvironment?

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

  /// Options for selectedCamera picker - automatically discovered by editor
  // @EditableOptions var selectedCameraOptions: [String] {
  //   return prerenderedEnvironment?.getAvailableCameras() ?? ["1"]
  // }

  // Main menu system
  private var mainMenu: MainMenu?
  private var showingMainMenu: Bool = false

  // Pickup view system
  private var pickupView: PickupView?
  private var showingPickupView: Bool = false

  // Dialog system
  private var dialogView: DialogView?
  // Scene script instance
  private var sceneScript: Script?

  // Room boundaries
  private let roomSize: Float = 10.0
  private var restrictMovementToRoom: Bool = false
  private let boxSize: Float = 2.0
  private let boxPosition: vec3 = vec3(3, 0, 3)

  init() {
    setupGameplay()
  }

  private func setupGameplay() {
    // Load scene and find Camera_1
    loadScene()

    // Load capsule mesh from GLB file
    loadCapsuleMesh()

    // Initialize dialog view
    dialogView = DialogView()

    // Initialize prerendered environment
    do {
      prerenderedEnvironment = try PrerenderedEnvironment(sceneName)
      // Sync the selectedCamera property with the actual current camera
      selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? "1"
    } catch {
      print("Failed to initialize PrerenderedEnvironment: \(error)")
    }

    // Initialize main menu
    mainMenu = MainMenu()

    // Initialize Jolt runtime (required before using any Jolt features)
    JoltRuntime.initialize()

    // Initialize physics system for collision body visualization
    // Set up collision filtering (required for PhysicsSystem)
    // Note: Object layers are 0-indexed, so numObjectLayers: 3 means we can use layers 0, 1, 2
    let numObjectLayers: UInt32 = 3  // 0=unused, 1=static, 2=dynamic
    let numBroadPhaseLayers: UInt32 = 2  // Keep it simple - 2 broad phase layers

    // Create broad phase layer interface
    let broadPhaseLayerInterface = BroadPhaseLayerInterfaceTable(
      numObjectLayers: numObjectLayers,
      numBroadPhaseLayers: numBroadPhaseLayers
    )
    // Map all object layers to the first broad phase layer (simple setup)
    broadPhaseLayerInterface.map(objectLayer: 1, to: 0)  // Static objects
    broadPhaseLayerInterface.map(objectLayer: 2, to: 0)  // Dynamic objects (if we add them)

    // Create object layer pair filter (allows all collisions)
    let objectLayerPairFilter = ObjectLayerPairFilterTable(numObjectLayers: numObjectLayers)
    // Enable collisions between all layers
    objectLayerPairFilter.enableCollision(1, 1)  // Static vs Static
    objectLayerPairFilter.enableCollision(1, 2)  // Static vs Dynamic
    objectLayerPairFilter.enableCollision(2, 2)  // Dynamic vs Dynamic

    // Create object vs broad phase layer filter
    let objectVsBroadPhaseLayerFilter = ObjectVsBroadPhaseLayerFilterTable(
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
    physicsSystem?.setGravity(Vec3(x: 0, y: -9.81, z: 0))

    // Store filters so they stay alive (PhysicsSystem only keeps references)
    self.broadPhaseLayerInterface = broadPhaseLayerInterface
    self.objectLayerPairFilter = objectLayerPairFilter
    self.objectVsBroadPhaseLayerFilter = objectVsBroadPhaseLayerFilter

    // Initialize debug renderer
    let debugProcs = DebugRendererImplementation()
    debugRenderer = DebugRenderer(procs: debugProcs)
    debugProcs.renderLoop = self

    // Create ground plane immediately (doesn't depend on scene)
    createGroundPlane()

    // Load collision bodies into physics system when scene is ready
    Task {
      // Wait for scene to load
      while scene == nil {
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
      }
      await MainActor.run {
        if let loadedScene = scene {
          loadCollisionBodiesIntoPhysics(scene: loadedScene)
          loadActionBodiesIntoPhysics(scene: loadedScene)
          loadTriggerBodiesIntoPhysics(scene: loadedScene)
          // Optimize broad phase after adding bodies (recommended before first Update)
          physicsSystem?.optimizeBroadPhase()

          // Create character controller now that physics is ready
          if let physicsSystem = physicsSystem {
            // Spawn at Entry_1 if present
            if let entryNode = loadedScene.rootNode.findNode(named: "Entry_1") {
              let entryWorld = calculateNodeWorldTransform(entryNode, scene: loadedScene)
              let extractedPos = vec3(entryWorld[3].x, entryWorld[3].y, entryWorld[3].z)
              let fwd = vec3(entryWorld[2].x, entryWorld[2].y, entryWorld[2].z)
              let yaw = atan2(fwd.x, fwd.z)
              let spawnRot = yaw - (.pi * 0.5)
              createCharacterController(at: extractedPos, rotation: spawnRot, in: physicsSystem)
            }
          }

          // Mark physics system as ready for updates
          physicsSystemReady = true
        }
      }
    }
  }

  private func loadScene() {
    Task {
      do {
        let scenePath = Bundle.game.path(forResource: "Scenes/\(sceneName)", ofType: "glb")!
        let assimpScene = try Assimp.Scene(
          file: scenePath,
          flags: [.triangulate, .flipUVs, .calcTangentSpace]
        )

        // Wrap in our Scene wrapper
        let scene = Scene(assimpScene)

        print(scene.rootNode)
        scene.cameras.forEach { print($0) }

        await MainActor.run {
          self.scene = scene

          // Load scene script class dynamically
          loadSceneScript()

          // Initialize active camera from scene using default name Camera_1
          self.syncActiveCamera(name: "Camera_1")

          // Load scene lights
          self.loadSceneLights()

          // Load foreground meshes (nodes with -fg suffix)
          self.loadForegroundMeshes(scene: scene)

          // Spawn at Entry_1 if present
          if let entryNode = scene.rootNode.findNode(named: "Entry_1") {
            let entryWorld = self.calculateNodeWorldTransform(entryNode, scene: scene)
            // Position from world transform translation (column 3, rows 0-2)
            // In GLMath mat4, [3] is the 4th column which contains translation
            let extractedPos = vec3(entryWorld[3].x, entryWorld[3].y, entryWorld[3].z)
            self.spawnPosition = extractedPos
            // Forward direction from world transform's third row (basis Z)
            let fwd = vec3(entryWorld[2].x, entryWorld[2].y, entryWorld[2].z)
            // Our movement uses forward = (sin(theta), 0, cos(theta)). Blender/glTF forward differs by ~90°.
            // Apply a yaw offset to align the exported arrow (forward) with our tank-forward.
            let yaw = atan2(fwd.x, fwd.z)
            self.spawnRotation = yaw - (.pi * 0.5)
            self.playerPosition = self.spawnPosition
            self.playerRotation = self.spawnRotation
            print("🚀 Spawned capsule at Entry_1: \(self.playerPosition)")
            print(
              "📐 Entry_1 world transform translation column [3]: (\(entryWorld[3].x), \(entryWorld[3].y), \(entryWorld[3].z))"
            )
            // Character controller will be created after physics system is ready (in setupGameplay)

            // Disable small-room clamping for real scene navigation
            self.restrictMovementToRoom = false
          }
        }
      } catch {
        fatalError("Failed to load scene: \(error)")
      }
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
        print("💡 Loaded light '\(lightName)' type: \(light.type)")
      } else {
        print("⚠️ Light node '\(lightName)' not found in scene graph")
      }
    }

    if sceneLights.isEmpty {
      print("⚠️ No lights found in scene")
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
            print("✅ Created foreground MeshInstance for node '\(name)' mesh \(i)")
          }
        }
      }

      // Recursively traverse children (even if this node doesn't have -fg, children might)
      for child in node.children {
        traverse(child)
      }
    }

    traverse(scene.rootNode)
    print("✅ Loaded \(foregroundMeshInstances.count) foreground mesh instances")
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

      print(
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

  /// Syncs `camera1`, its node/world transform and prerender near/far from the given camera name
  private func syncActiveCamera(name: String) {
    guard let scene = self.scene else { return }
    let nodeName = name
    if let node = scene.rootNode.findNode(named: nodeName) {
      camera1Node = node
      camera1WorldTransform = calculateNodeWorldTransform(node, scene: scene)
      print("✅ Active camera node: \(nodeName)")
      // Debug: Print camera transform
      let cameraPos = vec3(camera1WorldTransform[3].x, camera1WorldTransform[3].y, camera1WorldTransform[3].z)
      print("📷 Camera world transform position: \(cameraPos)")
    } else {
      print("⚠️ Camera node not found: \(nodeName)")
      camera1Node = nil
      camera1WorldTransform = mat4(1)
    }

    if let cam = scene.cameras.first(where: { $0.name == nodeName }) {
      camera1 = cam
      // Sync projection and mist params
      prerenderedEnvironment?.near = cam.clipPlaneNear
      prerenderedEnvironment?.far = cam.clipPlaneFar
      // If Blender mist settings are known, keep defaults (0.1 / 25.0) or adjust here
      print(
        "✅ Active camera params near=\(cam.clipPlaneNear) far=\(cam.clipPlaneFar) fov=\(cam.horizontalFOV) aspect=\(cam.aspect)"
      )
    } else {
      print("⚠️ Camera struct not found for name: \(nodeName)")
      camera1 = nil
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
        print("Failed to load capsule mesh: \(error)")
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
      mainMenu?.update(window: window, deltaTime: deltaTime)
    } else {
      // Only handle movement if dialog is not active (text is empty)
      let isDialogActive = dialogView?.text.isEmpty == false
      if !isDialogActive {
        // Handle WASD movement
        handleMovement(window.keyboard, deltaTime)
      }

      // Update prerendered environment animation
      prerenderedEnvironment?.update()
    }

    // Update dialog view
    dialogView?.update(deltaTime: deltaTime)

    // Update FPS (EMA)
    if deltaTime > 0 {
      let inst = 1.0 / deltaTime
      smoothedFPS = smoothedFPS * 0.9 + inst * 0.1
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if showingPickupView {
      // Forward input to pickup view
      pickupView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    if showingMainMenu {
      // Handle escape key with nested view support
      if key == .escape {
        // If there's a nested view (item/document), let MainMenu handle it first
        if let mainMenu = mainMenu, mainMenu.hasNestedViewOpen {
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
      mainMenu?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    } else {
      // Check if dialog is active (text is not empty)
      let isDialogActive = dialogView?.text.isEmpty == false

      // Handle dialog advancement keys first (these always work)
      switch key {
      case .f, .space, .enter, .numpadEnter:
        // Handle interaction - either advance dialog or interact with action
        // Dialog advancement keys always work, even when dialog is active
        if let dialogView = dialogView, !dialogView.text.isEmpty {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk
            //UISound.select()
          } else if dialogView.isFinished {
            // Dialog finished, close it
            //UISound.select()
            dialogView.text = ""
          }
        } else {
          // No dialog showing, handle interaction with detected action
          handleInteraction()
        }
        return

      default:
        break
      }

      // Skip other gameplay keys if dialog is active and not finished
      guard !isDialogActive else { return }

      // Handle other gameplay keys
      switch key {
      case .tab, .i:
        UISound.select()
        showMainMenu(tab: .inventory)

      case .m:
        UISound.select()
        showMainMenu(tab: .map)

      case .escape:
        // Could be used for other gameplay features
        break

      case .semicolon:
        UISound.select()
        prerenderedEnvironment?.cycleToNextCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .apostrophe:
        UISound.select()
        prerenderedEnvironment?.cycleToPreviousCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .graveAccent:
        UISound.select()
        prerenderedEnvironment?.switchToDebugCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        // Sync to corresponding Assimp camera (e.g., "1" -> "Camera_1", "stove.001" -> "Camera_stove.001")
        syncActiveCamera(name: "Camera_\(selectedCamera)")

      case .r:
        UISound.select()
        // Reset player to spawn
        playerPosition = spawnPosition
        playerRotation = spawnRotation

        // Also reset character controller if it exists
        if let characterController = characterController {
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
          print("🌫️ Debug: Mist visualization = \(env.showMist ? "ON" : "OFF")")
        }

      case .u:
        UISound.select()
        visualizePhysics.toggle()
        print("Debug renderer: \(visualizePhysics ? "ON" : "OFF")")

      default:
        break
      }
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    if showingPickupView {
      pickupView?.onMouseMove(window: window, x: x, y: y)
    } else if showingMainMenu {
      mainMenu?.onMouseMove(window: window, x: x, y: y)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if showingPickupView {
      pickupView?.onMouseButton(window: window, button: button, state: state, mods: mods)
    } else if showingMainMenu {
      mainMenu?.onMouseButton(window: window, button: button, state: state, mods: mods)
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if showingPickupView {
      pickupView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if showingMainMenu {
      // Handle right-click with nested view support (same as Escape)
      if button == .right {
        // If there's a nested view (item/document), let MainMenu handle it first
        if let mainMenu = mainMenu, mainMenu.hasNestedViewOpen {
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
      mainMenu?.onMouseButtonPressed(window: window, button: button, mods: mods)
    } else {
      // Handle interaction - either advance dialog or interact with action
      // Dialog advancement always works, even when dialog is active
      if button == .left {
        if let dialogView = dialogView, !dialogView.text.isEmpty {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk
            UISound.select()
          } else if dialogView.isFinished {
            // Dialog finished, close it
            dialogView.text = ""
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
    if showingPickupView {
      // No-op for pickup view
    } else if showingMainMenu {
      mainMenu?.onMouseButtonReleased(window: window, button: button, mods: mods)
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    if showingPickupView {
      pickupView?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    } else if showingMainMenu {
      mainMenu?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    }
  }

  private func showMainMenu(tab: MainMenuTabs.Tab) {
    mainMenu?.setActiveTab(tab, animated: false)
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
        Inventory.player1.slots[slotIndex] = SlotData(
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
  }

  private func loadSceneScript() {
    guard let scene else {
      logger.error("⚠️ No scene to load script for")
      return
    }
    guard let dialogView else {
      logger.error("⚠️ dialogView is nil")
      return
    }

    // Convert scene name to class name (e.g., "radar_office" -> "RadarOffice", "test" -> "Test")
    let className = sceneNameToClassName(sceneName)

    // Try to load the class using Objective-C runtime
    // NSClassFromString requires the full module name in Swift
    let fullClassName = "Game.\(className)"
    guard let scriptClass = NSClassFromString(fullClassName) as? Script.Type else {
      logger.error("⚠️ Could not load scene script class: \(fullClassName)")
      return
    }

    // Create an instance of the script class, passing dialogView to init
    sceneScript = scriptClass.init(scene: scene, dialogView: dialogView)
    // Set up pickup view callback
    sceneScript?.showPickupView = { [weak self] item, quantity in
      guard let self = self else { return false }
      // Show pickup view and wait for result
      return await self.showPickupView(item: item, quantity: quantity)
    }
    logger.info("✅ Loaded scene script: \(className)")

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

  private func handleInteraction() {
    guard let detectedActionName else { return }
    guard let sceneScript = sceneScript else { return }

    // Convert action name to method name (e.g., "Stove" -> "stove")
    let methodName = detectedActionName.prefix(1).lowercased() + detectedActionName.dropFirst()

    // Create selector for method with no parameters using Foundation
    let selector = Selector(methodName)

    // Check if the method exists and call it
    if sceneScript.responds(to: selector) {
      _ = sceneScript.perform(selector)
    } else {
      // If method not found, log a warning
      logger.warning("⚠️ Scene script does not respond to method: \(methodName)")
    }
  }

  private func callTriggerMethod(triggerName: String) {
    guard let sceneScript = sceneScript else { return }

    // Convert trigger name to method name (e.g., "Door" -> "door")
    let methodName = triggerName.prefix(1).lowercased() + triggerName.dropFirst()

    // Create selector for method with no parameters using Foundation
    let selector = Selector(methodName)

    // Check if the method exists and call it
    if sceneScript.responds(to: selector) {
      _ = sceneScript.perform(selector)
    } else {
      // If method not found, log a warning
      logger.warning("⚠️ Scene script does not respond to trigger method: \(methodName)")
    }
  }

  /// Get available cameras for editor integration
  public func getAvailableCameras() -> [String] {
    return prerenderedEnvironment?.getAvailableCameras() ?? ["1"]
  }

  private func createCharacterController(at position: vec3, rotation: Float, in system: PhysicsSystem) {
    guard characterController == nil else { return }  // Only create once

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

    // Create a sensor sphere in front of the capsule for detecting action triggers
    createCapsuleSensor(at: position, in: system)

    print("✅ Created character controller at position (\(position.x), \(position.y), \(position.z))")
  }

  private func createCapsuleSensor(at position: vec3, in system: PhysicsSystem) {
    guard let physicsSystem = physicsSystem else { return }
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
      print("✅ Created capsule sensor body ID: \(sensorBodyID)")
    } else {
      print("❌ Failed to create capsule sensor")
    }
  }

  private func handleMovement(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Tank controls: A/D rotate, W/S move forward/backward
    let rotationDelta = rotationSpeed * deltaTime

    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      playerRotation += rotationDelta
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      playerRotation -= rotationDelta
    }

    // Calculate forward direction from rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    // Update character controller if it exists
    if let characterController = characterController, let physicsSystem = physicsSystem {
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

      // Set horizontal velocity, preserve vertical
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
        // Update character controller (this does the physics movement)
        let characterLayer: ObjectLayer = 2  // Dynamic layer
        characterController.update(deltaTime: deltaTime, layer: characterLayer, in: physicsSystem)

        // Update physics system (jobSystem is required)
        if let jobSystem {
          physicsSystem.update(deltaTime: deltaTime, collisionSteps: 1, jobSystem: jobSystem)
        }
      }

      // Check for action body contacts (sensor bodies)
      // Query the sensor body to see if it's touching any action bodies
      detectedActionName = nil

      // Also check character controller contacts
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

        // Query for overlapping action bodies using collision query
        let sensorShape = SphereShape(radius: 0.5)
        var baseOffset = RVec3(x: sensorPosition.x, y: sensorPosition.y, z: sensorPosition.z)
        let queryResults = physicsSystem.collideShapeAll(
          shape: sensorShape,
          scale: Vec3(x: 1, y: 1, z: 1),
          baseOffset: &baseOffset
        )

        // Check if any of the colliding bodies are action bodies
        // JPH_CollideShapeResult has bodyID2 field (not bodyID)
        for result in queryResults {
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
      var newTriggers: Set<String> = []

      // Check character controller contacts for triggers
      for contact in contacts {
        if contact.isSensorB, let triggerName = triggerBodyNames[contact.bodyID] {
          let cleanName = triggerName.replacing(/-trigger$/, with: "")
          currentTriggers.append(cleanName)
          newTriggers.insert(cleanName)
        }
      }

      // Also check using collision query at player position (character controller position)
      // Use a sphere shape at the player position to detect triggers
      //let bodyInterface = physicsSystem.bodyInterface()
      let triggerCheckRadius: Float = 0.5  // Radius to check around player
      let triggerCheckShape = SphereShape(radius: triggerCheckRadius)
      var playerBaseOffset = RVec3(x: playerPosition.x, y: playerPosition.y, z: playerPosition.z)
      let triggerQueryResults = physicsSystem.collideShapeAll(
        shape: triggerCheckShape,
        scale: Vec3(x: 1, y: 1, z: 1),
        baseOffset: &playerBaseOffset
      )

      // Check for trigger bodies
      for result in triggerQueryResults {
        let bodyID = result.bodyID2
        if let triggerName = triggerBodyNames[bodyID] {
          let cleanName = triggerName.replacing(/-trigger$/, with: "")
          currentTriggers.append(cleanName)
          newTriggers.insert(cleanName)
        }
      }

      // Call trigger methods for newly entered triggers
      let newlyEnteredTriggers = newTriggers.subtracting(previousTriggers)
      for triggerName in newlyEnteredTriggers {
        callTriggerMethod(triggerName: triggerName)
      }

      // Update previous triggers for next frame
      previousTriggers = newTriggers

      // Read position back from character controller
      let characterPos = characterController.position
      playerPosition = vec3(characterPos.x, characterPos.y, characterPos.z)
      //    } else {
      //      // Fallback to manual movement if character controller not available
      //      // Check for speed boost (Shift key)
      //      let speedMultiplier: Float
      //      if keyboard.state(of: .leftShift) == .pressed || keyboard.state(of: .rightShift) == .pressed {
      //        speedMultiplier = 2.5  // 2.5x speed when holding Shift
      //      } else {
      //        speedMultiplier = 1.0
      //      }
      //      let moveDistance = moveSpeed * speedMultiplier * deltaTime
      //
      //      if keyboard.state(of: .w) == .pressed {
      //        playerPosition += forward * moveDistance
      //      }
      //      if keyboard.state(of: .s) == .pressed {
      //        playerPosition -= forward * moveDistance
      //      }
      //
      //      if restrictMovementToRoom {
      //        // Simple collision with room boundaries
      //        let halfRoom = roomSize / 2.0
      //        playerPosition.x = max(-halfRoom, min(halfRoom, playerPosition.x))
      //        playerPosition.z = max(-halfRoom, min(halfRoom, playerPosition.z))
      //      }
    }
  }

  func draw() {
    if showingPickupView {
      // Draw pickup view
      pickupView?.draw()
    } else if showingMainMenu {
      // Draw main menu
      mainMenu?.draw()
    } else {
      // Set up 3D rendering
      let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)

      // Use Camera_1 projection if available, otherwise fallback to default
      let projection: mat4
      if let camera1 = camera1 {
        // Check if camera is orthographic (FOV is 0 or orthographicWidth is set)
        let isOrthographic = camera1.horizontalFOV == 0.0 || camera1.orthographicWidth > 0.0

        if isOrthographic {
          // Orthographic camera: use orthographicWidth (half width) and aspect ratio
          let orthoWidth = camera1.orthographicWidth > 0.0 ? camera1.orthographicWidth : 1.0

          // IMPORTANT: Use camera's stored aspect ratio if available, otherwise viewport aspect
          let finalAspect: Float
          if camera1.aspect > 0 {
            finalAspect = camera1.aspect
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

          projection = GLMath.ortho(left, right, bottom, top, camera1.clipPlaneNear, camera1.clipPlaneFar)

          print(
            "📐 Using orthographic camera: width=\(orthoWidth * 2), aspect=\(finalAspect), near=\(camera1.clipPlaneNear), far=\(camera1.clipPlaneFar)"
          )
        } else {
          // Perspective camera: use existing FOV calculation
          // IMPORTANT: Use camera's stored aspect ratio if available, otherwise viewport aspect
          // The prerendered images were rendered with a specific aspect ratio, so we should match it
          let finalAspect: Float
          if camera1.aspect > 0 {
            // Use camera's aspect ratio (this is what the prerendered images were rendered with)
            finalAspect = camera1.aspect
          } else {
            // Fallback to viewport aspect ratio
            finalAspect = aspectRatio
          }

          // Convert horizontal FOV to vertical FOV
          // GLMath.perspective expects vertical FOV (fovy), but Assimp gives us horizontal FOV
          // Formula: verticalFOV = 2 * atan(tan(horizontalFOV / 2) / aspectRatio)
          let horizontalFOVHalf = camera1.horizontalFOV / 2.0
          let verticalFOV = 2.0 * atan(tan(horizontalFOVHalf) / finalAspect)

          projection = GLMath.perspective(verticalFOV, finalAspect, camera1.clipPlaneNear, camera1.clipPlaneFar)

          // Debug: Print aspect ratio mismatch if significant
          if abs(finalAspect - aspectRatio) > 0.01 {
            print("⚠️ Aspect ratio mismatch: camera=\(finalAspect), viewport=\(aspectRatio)")
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
      let view: mat4
      let cameraWorld: mat4
      // Check if camera world transform is valid (not identity)
      if camera1WorldTransform != mat4(1) {
        cameraWorld = camera1WorldTransform
        // The view matrix is the inverse of the camera's world transform
        // This matches how the prerendered images were rendered
        view = inverse(cameraWorld)
      } else {
        // Fallback: use identity view matrix if camera not available
        cameraWorld = mat4(1)
        view = mat4(1)
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

      // Draw 3D debug arrows for all Entry_* nodes
      //      if let loadedScene = scene {
      //drawEntryArrows(in: loadedScene, projection: projection, view: view)
      //      }

      // Update debug renderer camera and draw if enabled
      if visualizePhysics, let debugRenderer = debugRenderer {
        currentProjection = projection
        currentView = view

        // Set camera position for debug renderer (extract from view matrix)
        let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)
        debugRenderer.setCameraPosition(RVec3(x: cameraPosition.x, y: cameraPosition.y, z: cameraPosition.z))

        // Call nextFrame to clear previous frame's geometry
        debugRenderer.nextFrame()

        // Draw all physics bodies using Jolt's drawBodies (draws actual geometry, not just AABBs)
        if let physicsSystem = physicsSystem {
          physicsSystem.drawBodies(debugRenderer: debugRenderer)
        }

        // Draw entry arrows using Jolt debug renderer
        if let loadedScene = scene {
          drawEntryArrowsWithJolt(scene: loadedScene, debugRenderer: debugRenderer)
        }

        debugRenderer.drawMarker(RVec3(x: 0, y: 0, z: 0), color: 0xFFFF_00FF, size: 2.0)
      }

      // Debug overlay (top-left)
      drawDebugInfo()

      // Draw dialog view (on top of everything)
      GraphicsContext.current?.renderer.withUIContext {
        dialogView?.draw()
      }
    }
  }
}

// MARK: - Debug

extension MainLoop {
  private func drawDebugInfo() {
    let overlayLines = [
      //String(format: "FPS: %.0f", smoothedFPS),
      //"Scene: \(sceneName)",
      "Camera: \(selectedCamera)",

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
        ? "Action: \(detectedActionName!.prefix(1).lowercased() + detectedActionName!.dropFirst())" : "Action: none",

      currentTriggers.isEmpty
        ? "Triggers: none"
        : "Triggers: \(currentTriggers.map { $0.prefix(1).lowercased() + $0.dropFirst() }.joined(separator: ", "))",
    ]

    let overlay = overlayLines.joined(separator: "\n")

    overlay.draw(
      at: Point(20, Engine.viewportSize.height - 20),
      style: .itemDescription.withMonospacedDigits(true),
      anchor: .topLeft
    )
  }

  private func drawEntryArrows(in scene: Scene, projection: mat4, view: mat4) {
    func traverse(_ node: Node) {
      if let name = node.name, name.hasPrefix("Entry_") {
        let world = calculateNodeWorldTransform(node, scene: scene)
        let origin = vec3(world[3].x, world[3].y, world[3].z)
        let forward = vec3(world[2].x, world[2].y, world[2].z)
        origin.drawDebugArrow3D(
          direction: forward,
          projection: projection,
          view: view,
          depthTest: false
        )
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func createGroundPlane() {
    guard let physicsSystem = physicsSystem else { return }
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
      print("✅ Created ground plane body ID: \(groundBodyID)")
    } else {
      print("❌ Failed to create ground plane")
    }
  }

  private func loadCollisionBodiesIntoPhysics(scene: Scene) {
    guard let physicsSystem = physicsSystem else { return }
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
              print("✅ Created collision body ID: \(bodyID) for node '\(name)'")
            } else {
              print("❌ Failed to create collision body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func loadActionBodiesIntoPhysics(scene: Scene) {
    guard let physicsSystem = physicsSystem else { return }
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
              print("✅ Created action trigger body ID: \(bodyID) for node '\(name)'")
            } else {
              print("❌ Failed to create action trigger body for node '\(name)'")
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func loadTriggerBodiesIntoPhysics(scene: Scene) {
    guard let physicsSystem = physicsSystem else { return }
    let bodyInterface = physicsSystem.bodyInterface()

    // Simple object layer for static trigger bodies (same as collision bodies)
    let staticLayer: ObjectLayer = 1

    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-trigger") {
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
              print("✅ Created trigger body ID: \(bodyID) for node '\(name)'")
            } else {
              print("❌ Failed to create trigger body for node '\(name)'")
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

  private func extractRotationQuat(from transform: mat4) -> Quat {
    // Extract rotation from 3x3 upper-left matrix
    // Convert matrix to quaternion
    let m = transform

    // Matrix to quaternion conversion
    let trace = m[0].x + m[1].y + m[2].z

    let q: Quat
    if trace > 0 {
      let s = sqrt(trace + 1.0) * 2.0  // s = 4 * qw
      let w = 0.25 * s
      let x = (m[2].y - m[1].z) / s
      let y = (m[0].z - m[2].x) / s
      let z = (m[1].x - m[0].y) / s
      q = Quat(x: x, y: y, z: z, w: w)
    } else if (m[0].x > m[1].y) && (m[0].x > m[2].z) {
      let s = sqrt(1.0 + m[0].x - m[1].y - m[2].z) * 2.0  // s = 4 * qx
      let w = (m[2].y - m[1].z) / s
      let x = 0.25 * s
      let y = (m[0].y + m[1].x) / s
      let z = (m[0].z + m[2].x) / s
      q = Quat(x: x, y: y, z: z, w: w)
    } else if m[1].y > m[2].z {
      let s = sqrt(1.0 + m[1].y - m[0].x - m[2].z) * 2.0  // s = 4 * qy
      let w = (m[0].z - m[2].x) / s
      let x = (m[0].y + m[1].x) / s
      let y = 0.25 * s
      let z = (m[1].z + m[2].y) / s
      q = Quat(x: x, y: y, z: z, w: w)
    } else {
      let s = sqrt(1.0 + m[2].z - m[0].x - m[1].y) * 2.0  // s = 4 * qz
      let w = (m[1].x - m[0].y) / s
      let x = (m[0].z + m[2].x) / s
      let y = (m[1].z + m[2].y) / s
      let z = 0.25 * s
      q = Quat(x: x, y: y, z: z, w: w)
    }

    // Normalize quaternion (required by Jolt)
    let length = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    guard length > 0.0001 else {
      // If quaternion is degenerate, return identity
      return Quat.identity
    }
    let invLength = 1.0 / length
    return Quat(x: q.x * invLength, y: q.y * invLength, z: q.z * invLength, w: q.w * invLength)
  }

  private func drawCollisionBodies(scene: Scene, debugRenderer: DebugRenderer) {
    func traverse(_ node: Node) {
      if let name = node.name, name.contains("-col") {
        let worldTransform = calculateNodeWorldTransform(node, scene: scene)

        // Get mesh from this node
        if node.numberOfMeshes > 0 {
          let meshIndex = node.meshes[0]
          if meshIndex < scene.meshes.count {
            let mesh = scene.meshes[Int(meshIndex)]

            // Calculate bounding box from mesh vertices
            if let aabb = calculateMeshAABB(mesh: mesh, transform: worldTransform) {
              // Draw wireframe box using debug renderer
              let cyanColor: Jolt.Color = 0xFF00_FFFF  // RGBA: cyan
              debugRenderer.drawWireBox(aabb, color: cyanColor)
            }
          }
        }
      }
      for child in node.children { traverse(child) }
    }
    traverse(scene.rootNode)
  }

  private func calculateMeshAABB(mesh: Assimp.Mesh, transform: mat4) -> AABB? {
    guard mesh.numberOfVertices > 0 else { return nil }

    let vertices = mesh.vertices  // Mesh has a 'vertices' property, not 'positions'

    // Transform first vertex to initialize min/max
    let firstPos = vec3(
      Float(vertices[0]),
      Float(vertices[1]),
      Float(vertices[2])
    )
    let firstWorld = transform * vec4(firstPos.x, firstPos.y, firstPos.z, 1.0)
    var minPoint = vec3(firstWorld.x, firstWorld.y, firstWorld.z)
    var maxPoint = minPoint

    // Transform all vertices and find min/max
    for i in 0..<mesh.numberOfVertices {
      let pos = vec3(
        Float(vertices[i * 3 + 0]),
        Float(vertices[i * 3 + 1]),
        Float(vertices[i * 3 + 2])
      )
      let worldPos = transform * vec4(pos.x, pos.y, pos.z, 1.0)
      let worldVec = vec3(worldPos.x, worldPos.y, worldPos.z)

      minPoint.x = min(minPoint.x, worldVec.x)
      minPoint.y = min(minPoint.y, worldVec.y)
      minPoint.z = min(minPoint.z, worldVec.z)
      maxPoint.x = max(maxPoint.x, worldVec.x)
      maxPoint.y = max(maxPoint.y, worldVec.y)
      maxPoint.z = max(maxPoint.z, worldVec.z)
    }

    return AABB(
      min: Vec3(x: minPoint.x, y: minPoint.y, z: minPoint.z), max: Vec3(x: maxPoint.x, y: maxPoint.y, z: maxPoint.z))
  }

  private func drawEntryArrowsWithJolt(scene: Scene, debugRenderer: DebugRenderer) {
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

// MARK: - Debug Renderer Implementation

private final class DebugRendererImplementation: DebugRendererProcs {
  weak var renderLoop: MainLoop?

  func drawLine(from: RVec3, to: RVec3, color: Jolt.Color) {
    guard let renderLoop = renderLoop else { return }
    let fromVec = vec3(Float(from.x), Float(from.y), Float(from.z))
    let toVec = vec3(Float(to.x), Float(to.y), Float(to.z))

    // Convert Jolt.Color (RGBA packed UInt32) to Color
    let lineColor = Color(color)

    MainActor.assumeIsolated {
      // Use GLRenderer directly instead of drawDebugLine
      guard let renderer = GraphicsContext.current?.renderer as? GLRenderer else { return }
      renderer.drawDebugLine3D(
        from: fromVec,
        to: toVec,
        color: lineColor,
        projection: renderLoop.currentProjection,
        view: renderLoop.currentView,
        lineThickness: 0.005,  // Thin line for wireframe
        depthTest: false  // Always on top for debug overlay
      )
    }
  }

  func drawTriangle(
    v1: RVec3, v2: RVec3, v3: RVec3, color: Jolt.Color, castShadow: DebugRenderer.CastShadow
  ) {
    // Draw triangle as wireframe using lines
    drawLine(from: v1, to: v2, color: color)
    drawLine(from: v2, to: v3, color: color)
    drawLine(from: v3, to: v1, color: color)
  }

  func drawText3D(position: RVec3, text: String, color: Jolt.Color, height: Float) {
    print(#function, text)
    // For now, just ignore text rendering
    // TODO: Implement 3D text rendering if needed
  }
}
