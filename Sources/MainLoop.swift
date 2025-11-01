import Assimp

@Editor final class MainLoop: RenderLoop {
  // Scene configuration
  private let sceneName: String = "test"

  // Gameplay state
  private var playerPosition: vec3 = vec3(0, 0, 0)
  private var playerRotation: Float = 0.0
  private var moveSpeed: Float = 5.0
  private var rotationSpeed: Float = 2.0  // radians per second
  private var smoothedFPS: Float = 60.0
  private var spawnPosition: vec3 = vec3(0, 0, 0)
  private var spawnRotation: Float = 0.0

  // Capsule mesh from GLB file
  private var capsuleMeshInstances: [MeshInstance] = []

  // Scene and camera
  private var scene: Assimp.Scene?
  private var camera1: Assimp.Camera?
  private var camera1Node: Assimp.Node?
  private var camera1WorldTransform: mat4 = mat4(1)

  // Prerendered environment renderer
  private var prerenderedEnvironment: PrerenderedEnvironment?

  @Editable var nearestNeighbor: Bool = true {
    didSet {
      prerenderedEnvironment?.nearestNeighborFiltering = nearestNeighbor
    }
  }

  @Editable var selectedCamera: String = "1" {
    didSet {
      if selectedCamera != oldValue {
        try? prerenderedEnvironment?.switchToCamera(selectedCamera)
      }
    }
  }

  /// Options for selectedCamera picker - automatically discovered by editor
  @EditableOptions var selectedCameraOptions: [String] {
    return prerenderedEnvironment?.getAvailableCameras() ?? ["1"]
  }

  // Main menu system
  private var mainMenu: MainMenu?
  private var showingMainMenu: Bool = false

  // Room boundaries
  private let roomSize: Float = 10.0
  private var restrictMovementToRoom: Bool = false
  private let boxSize: Float = 2.0
  private let boxPosition: vec3 = vec3(3, 0, 3)

  // Debug: toggle depth clearing (so capsule renders on top)
  private var debugClearDepth: Bool = false

  init() {
    setupGameplay()
  }

  private func setupGameplay() {
    // Load scene and find Camera_1
    loadScene()

    // Load capsule mesh from GLB file
    loadCapsuleMesh()

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
  }

  private func loadScene() {
    Task {
      do {
        let scenePath = Bundle.game.path(forResource: "Scenes/\(sceneName)", ofType: "glb")!
        let scene = try Assimp.Scene(
          file: scenePath,
          flags: [.triangulate, .flipUVs, .calcTangentSpace]
        )

        print(scene.rootNode)
        scene.cameras.forEach { print($0) }

        await MainActor.run {
          self.scene = scene

          // Initialize active camera from scene using default name Camera_1
          self.syncActiveCamera(name: "Camera_1")

          // Spawn at Entry_1 if present
          if let entryNode = scene.rootNode.findNode(named: "Entry_1") {
            let entryWorld = self.calculateNodeWorldTransform(entryNode, scene: scene)
            // Position from world transform translation
            self.spawnPosition = vec3(entryWorld[3].x, entryWorld[3].y, entryWorld[3].z)
            // Forward direction from world transform's third row (basis Z)
            let fwd = vec3(entryWorld[2].x, entryWorld[2].y, entryWorld[2].z)
            // Our movement uses forward = (sin(theta), 0, cos(theta)). Blender/glTF forward differs by ~90°.
            // Apply a yaw offset to align the exported arrow (forward) with our tank-forward.
            let yaw = atan2(fwd.x, fwd.z)
            self.spawnRotation = yaw - (.pi * 0.5)
            self.playerPosition = self.spawnPosition
            self.playerRotation = self.spawnRotation
            print("🚀 Spawned capsule at Entry_1: \(self.playerPosition)")
            // Disable small-room clamping for real scene navigation
            self.restrictMovementToRoom = false
          }
        }
      } catch {
        fatalError("Failed to load scene: \(error)")
      }
    }
  }

  /// Syncs `camera1`, its node/world transform and prerender near/far from the given camera name
  private func syncActiveCamera(name: String) {
    guard let scene = self.scene else { return }
    let nodeName = name
    if let node = scene.rootNode.findNode(named: nodeName) {
      camera1Node = node
      camera1WorldTransform = calculateNodeWorldTransform(node, scene: scene)
      print("✅ Active camera node: \(nodeName)")
    } else {
      print("⚠️ Camera node not found: \(nodeName)")
    }

    if let cam = scene.cameras.first(where: { $0.name == nodeName }) {
      camera1 = cam
      // Sync projection and mist params
      prerenderedEnvironment?.near = cam.clipPlaneNear
      prerenderedEnvironment?.far = cam.clipPlaneFar
      // If Blender mist settings are known, keep defaults (0.1 / 25.0) or adjust here
      print("✅ Active camera params near=\(cam.clipPlaneNear) far=\(cam.clipPlaneFar) fov=\(cam.horizontalFOV)")
    } else {
      print("⚠️ Camera struct not found for name: \(nodeName)")
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
  private func calculateNodeWorldTransform(_ node: Assimp.Node, scene: Assimp.Scene) -> mat4 {
    var transform = convertAssimpMatrix(node.transformation)
    var currentNode = node

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
    if showingMainMenu {
      // Update main menu
      mainMenu?.update(window: window, deltaTime: deltaTime)
    } else {
      // Handle WASD movement
      handleMovement(window.keyboard, deltaTime)

      // Update prerendered environment animation
      prerenderedEnvironment?.update()
    }

    // Update FPS (EMA)
    if deltaTime > 0 {
      let inst = 1.0 / deltaTime
      smoothedFPS = smoothedFPS * 0.9 + inst * 0.1
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if showingMainMenu {
      // Handle escape to close main menu
      if key == .escape {
        UISound.select()
        hideMainMenu()
        return
      }

      // Forward other input to main menu
      mainMenu?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    } else {
      // Handle gameplay keys
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
        // Try to sync to corresponding Assimp camera (e.g., "1" -> "Camera_1")
        if let name = Int(selectedCamera) { syncActiveCamera(name: "Camera_\(name)") }

      case .apostrophe:
        UISound.select()
        prerenderedEnvironment?.cycleToPreviousCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        if let name = Int(selectedCamera) { syncActiveCamera(name: "Camera_\(name)") }

      case .graveAccent:
        UISound.select()
        prerenderedEnvironment?.switchToDebugCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera
        if let name = Int(selectedCamera) { syncActiveCamera(name: "Camera_\(name)") }

      case .r:
        UISound.select()
        // Reset player to spawn
        playerPosition = spawnPosition
        playerRotation = spawnRotation

      case .c:
        UISound.select()
        // Toggle depth clearing for debugging
        debugClearDepth.toggle()
        print("🔧 Debug: Depth clearing \(debugClearDepth ? "enabled" : "disabled")")

      case .l:
        UISound.select()
        // Cycle through mist debug modes: normal -> mist only -> mist overlay -> normal
        if let env = prerenderedEnvironment {
          env.debugMistMode = (env.debugMistMode + 1) % 3
          let modeNames = ["normal", "mist only", "mist overlay"]
          print("🌫️ Debug: Mist visualization mode = \(modeNames[env.debugMistMode])")
        }

      default:
        break
      }

    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    if showingMainMenu {
      mainMenu?.onMouseMove(window: window, x: x, y: y)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if showingMainMenu {
      mainMenu?.onMouseButton(window: window, button: button, state: state, mods: mods)
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if showingMainMenu {
      mainMenu?.onMouseButtonPressed(window: window, button: button, mods: mods)
    }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if showingMainMenu {
      mainMenu?.onMouseButtonReleased(window: window, button: button, mods: mods)
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    if showingMainMenu {
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

  /// Get available cameras for editor integration
  public func getAvailableCameras() -> [String] {
    return prerenderedEnvironment?.getAvailableCameras() ?? ["1"]
  }

  private func handleMovement(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Tank controls: A/D rotate, W/S move forward/backward
    let rotationDelta = rotationSpeed * deltaTime

    if keyboard.state(of: .a) == .pressed {
      playerRotation += rotationDelta
    }
    if keyboard.state(of: .d) == .pressed {
      playerRotation -= rotationDelta
    }

    // Calculate forward direction from rotation
    let forwardX = GLMath.sin(playerRotation)
    let forwardZ = GLMath.cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)

    let moveDistance = moveSpeed * deltaTime

    if keyboard.state(of: .w) == .pressed {
      playerPosition += forward * moveDistance
    }
    if keyboard.state(of: .s) == .pressed {
      playerPosition -= forward * moveDistance
    }

    if restrictMovementToRoom {
      // Simple collision with room boundaries
      let halfRoom = roomSize / 2.0
      playerPosition.x = max(-halfRoom, min(halfRoom, playerPosition.x))
      playerPosition.z = max(-halfRoom, min(halfRoom, playerPosition.z))

      //      // Simple collision with box
      //      let halfBox = boxSize / 2.0
      //      let diff = playerPosition - boxPosition
      //      let diffX = diff.x * diff.x
      //      let diffY = diff.y * diff.y
      //      let diffZ = diff.z * diff.z
      //      let distanceToBox = GLMath.sqrt(diffX + diffY + diffZ)
      //      if distanceToBox < halfBox + 0.5 {  // 0.5 is player radius
      //        // Push player away from box
      //        let direction = diff / distanceToBox
      //        playerPosition = boxPosition + direction * (halfBox + 0.5)
      //      }
    }
  }

  func draw() {
    if showingMainMenu {
      // Draw main menu
      mainMenu?.draw()
    } else {
      // Set up 3D rendering
      let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)

      // Use Camera_1 projection if available, otherwise fallback to default
      let projection: mat4
      if let camera1 = camera1 {
        // Use the aspect ratio from the viewport, or camera's aspect if available
        let finalAspect = camera1.aspect > 0 ? camera1.aspect : aspectRatio
        projection = GLMath.perspective(camera1.horizontalFOV, finalAspect, camera1.clipPlaneNear, camera1.clipPlaneFar)
      } else {
        projection = GLMath.perspective(45.0, aspectRatio, 0.1, 100.0)
      }

      // Render prerendered environment first (as background)
      prerenderedEnvironment?.render(projectionMatrix: projection)

      // Clear depth buffer if debug mode is enabled (so capsule renders on top)
      if debugClearDepth {
        glClear(GL_DEPTH_BUFFER_BIT)
      }

      // Get view matrix from camera node's world transform
      // In glTF/Assimp, the camera node's transform IS the camera transform in world space
      // We just invert it to get the view matrix
      let view: mat4
      let cameraWorld: mat4
      if camera1Node != nil {
        // Use the camera node's world transform directly
        cameraWorld = camera1WorldTransform
        // Invert to get view matrix (view = inverse(camera_world_transform))
        view = inverse(cameraWorld)
      } else {
        // Fallback: use identity view matrix if camera not available (shouldn't happen normally)
        print("⚠️ Warning: Scene camera not available, using identity view matrix")
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
        var modelMatrix = GLMath.translate(mat4(1), playerPosition)
        modelMatrix = GLMath.rotate(modelMatrix, playerRotation, vec3(0, 1, 0))

        for meshInstance in capsuleMeshInstances {
          // Combine the mesh's original transform with player transform
          let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix

          // Extract camera position from world transform (4th column)
          let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)

          meshInstance.draw(
            projection: projection,
            view: view,
            modelMatrix: combinedModelMatrix,
            cameraPosition: cameraPosition,
            lightDirection: vec3(0, -1, 0),
            lightColor: vec3(1, 1, 1),
            lightIntensity: 1.0,
            fillLightDirection: vec3(-0.3, -0.5, -0.2),
            fillLightColor: vec3(0.8, 0.9, 1.0),
            fillLightIntensity: 0.4,
            diffuseOnly: false
          )
        }
      }

      // Draw 3D debug arrows for all Entry_* nodes
      if let loadedScene = scene {
        drawEntryArrows(in: loadedScene, projection: projection, view: view)
      }

      // Debug overlay (top-left)
      drawDebugInfo(showDepthClearDebug: debugClearDepth)
    }
  }
}

// MARK: - Debug

extension MainLoop {
  private func drawDebugInfo(showDepthClearDebug: Bool = false) {
    var overlayLines = [
      //String(format: "FPS: %.0f", smoothedFPS),
      "Scene: \(sceneName)",
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
      //"Health: 100% ",
      //"Triggers: none",
      //"Actions: none",
    ]

    if showDepthClearDebug {
      overlayLines.append("🔧 Depth Clear: ON (C to toggle)")
    }

    let overlay = overlayLines.joined(separator: "\n")

    overlay.draw(
      at: Point(20, Engine.viewportSize.height - 20),
      style: .itemDescription.withMonospacedDigits(true),
      anchor: .topLeft
    )
  }

  private func drawEntryArrows(in scene: Assimp.Scene, projection: mat4, view: mat4) {
    func traverse(_ node: Assimp.Node) {
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
}
