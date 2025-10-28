import Assimp

/// The main game loop that handles rendering and input.
@Editor final class MainLoop: RenderLoop {

  // Gameplay state
  private var playerPosition: vec3 = vec3(0, 0, 0)
  private var playerRotation: Float = 0.0
  private var moveSpeed: Float = 5.0

  // Camera for gameplay
  private var camera = FixedCamera()

  // Simple pill mesh (we'll create this procedurally)
  private var pillMesh: MeshInstance?

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
  private let boxSize: Float = 2.0
  private let boxPosition: vec3 = vec3(3, 0, 3)

  init() {
    setupGameplay()
  }

  private func setupGameplay() {
    // Set up camera to look down at the gameplay area
    camera.target = vec3(0, 0, 0)
    camera.position = vec3(0, 8, 5)

    // Create a simple pill mesh (capsule)
    createPillMesh()

    // Initialize prerendered environment
    do {
      prerenderedEnvironment = try PrerenderedEnvironment()
      // Sync the selectedCamera property with the actual current camera
      selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? "1"
    } catch {
      print("Failed to initialize PrerenderedEnvironment: \(error)")
    }

    // Initialize main menu
    mainMenu = MainMenu()
  }

  private func createPillMesh() {
    // Generate a procedural pill mesh
    //let (vertices, indices) = PillMeshGenerator.generatePill(diameter: 1.0, height: 2.0, segments: 16)

    // TODO: Create a proper MeshInstance from the procedural data
    // For now, we'll just store the data and create a simple placeholder
    //print("Generated pill mesh with \(vertices.count / 8) vertices and \(indices.count / 3) triangles")

    // Create a simple box as placeholder until we implement proper procedural mesh loading
    pillMesh = nil  // No mesh for now
  }

  func update(window: Window, deltaTime: Float) {
    if showingMainMenu {
      // Update main menu
      mainMenu?.update(window: window, deltaTime: deltaTime)
    } else {
      // Handle WASD movement
      handleMovement(window.keyboard, deltaTime)

      // Update camera to follow player
      camera.follow(playerPosition)

      // Update prerendered environment animation
      prerenderedEnvironment?.update()
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

      case .apostrophe:
        UISound.select()
        prerenderedEnvironment?.cycleToPreviousCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera

      case .graveAccent:
        UISound.select()
        prerenderedEnvironment?.switchToDebugCamera()
        selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? selectedCamera

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
    showingMainMenu = true
    mainMenu?.setActiveTab(tab)
  }

  private func hideMainMenu() {
    showingMainMenu = false
  }

  /// Get available cameras for editor integration
  public func getAvailableCameras() -> [String] {
    return prerenderedEnvironment?.getAvailableCameras() ?? ["1"]
  }

  private func handleMovement(_ keyboard: Keyboard, _ deltaTime: Float) {
    let moveDistance = moveSpeed * deltaTime

    // WASD movement
    if keyboard.state(of: .w) == .pressed {
      playerPosition.z -= moveDistance
    }
    if keyboard.state(of: .s) == .pressed {
      playerPosition.z += moveDistance
    }
    if keyboard.state(of: .a) == .pressed {
      playerPosition.x -= moveDistance
    }
    if keyboard.state(of: .d) == .pressed {
      playerPosition.x += moveDistance
    }

    // Simple collision with room boundaries
    let halfRoom = roomSize / 2.0
    playerPosition.x = max(-halfRoom, min(halfRoom, playerPosition.x))
    playerPosition.z = max(-halfRoom, min(halfRoom, playerPosition.z))

    // Simple collision with box
    let halfBox = boxSize / 2.0
    let diff = playerPosition - boxPosition
    let diffX = diff.x * diff.x
    let diffY = diff.y * diff.y
    let diffZ = diff.z * diff.z
    let distanceToBox = GLMath.sqrt(diffX + diffY + diffZ)
    if distanceToBox < halfBox + 0.5 {  // 0.5 is player radius
      // Push player away from box
      let direction = diff / distanceToBox
      playerPosition = boxPosition + direction * (halfBox + 0.5)
    }
  }

  func draw() {
    if showingMainMenu {
      // Draw main menu
      mainMenu?.draw()
    } else {
      // Render prerendered environment first (as background)
      if let env = prerenderedEnvironment {
        env.render()
      }

      //    // Set up 3D rendering
      //    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
      //    let projection = GLMath.perspective(45.0, aspectRatio, 0.1, 100.0)
      //    let view = camera.getViewMatrix()
      //
      //    // Draw player pill
      //    if let pill = pillMesh {
      //      let modelMatrix = GLMath.translate(mat4(1), playerPosition)
      //      pill.draw(
      //        projection: projection,
      //        view: view,
      //        modelMatrix: modelMatrix,
      //        cameraPosition: camera.position,
      //        lightDirection: vec3(0, -1, 0),
      //        lightColor: vec3(1, 1, 1),
      //        lightIntensity: 1.0,
      //        fillLightDirection: vec3(-0.3, -0.5, -0.2),
      //        fillLightColor: vec3(0.8, 0.9, 1.0),
      //        fillLightIntensity: 0.4,
      //        diffuseOnly: false
      //      )
      //      //    } else {
      //      //      // TODO: Draw procedural pill mesh directly
      //      //      print("No pill mesh loaded - procedural mesh not yet implemented")
      //    }
    }
  }

  private func drawRoom() {
    // Simple room visualization - just draw the floor
    // TODO: Add proper room mesh
  }

  private func drawBox() {
    // Simple box obstacle
    // TODO: Add proper box mesh
  }
}
