import Assimp
import CJolt
import Foundation
import Jolt

private let startingScene = "tunnels"
private let startingEntry = "1"

// private let startingScene = "nexus"
// private let startingEntry = "8"

// private let startingScene = "chiefs_office"
// private let startingEntry = "1"

// private let startingScene = "shooting_range"
// private let startingEntry = "hallway"

@Editable final class MainLoop: RenderLoop {
  static var shared: MainLoop?

  // Scene configuration
  private(set) var sceneName: String = startingScene
  var currentAreaName: String?
  private var needsInitialCameraTriggerSync: Bool = true

  func shouldForceCameraTriggerSync() -> Bool {
    return needsInitialCameraTriggerSync
  }

  func markCameraTriggerSynced() {
    needsInitialCameraTriggerSync = false
  }

  // Gameplay state
  private var smoothedFPS: Float = 60.0

  // Capsule mesh from GLB file
  private var capsuleMeshInstances: [MeshInstance] = []

  // Foreground meshes from scene (nodes with -fg suffix)
  private var foregroundMeshInstances: [MeshInstance] = []

  // Capsule height offset - adjust if capsule origin is at center instead of bottom
  @Editor(0.0...2.0) var capsuleHeightOffset: Float = 1.2

  // Systems
  private var physicsWorld: PhysicsWorld!
  private var cameraSystem: CameraSystem!
  private var playerController: PlayerController!
  private var interactionSystem: InteractionSystem!
  private var enemySystem: EnemySystem!
  private var weaponSystem: WeaponSystem!

  // Expose player position/rotation for rendering and debug
  var playerPosition: vec3 {
    return playerController.position
  }
  var playerRotation: Float {
    return playerController.rotation
  }

  var currentProjection: mat4 = mat4(1)  // Accessible by debug renderer implementation
  var currentView: mat4 = mat4(1)  // Accessible by debug renderer implementation

  @Editor var visualizePhysics: Bool = false
  @Editor var visualizeEntries: Bool = false
  @Editor var disableDepth: Bool = false
  @Editor @ConfigValue var disableEnemies: Bool = false
  private var showDebugText: Bool = true
  @Editor var showEnemyDebugOverlay: Bool = false

  @Editor(-1.0...100.0) var mistDepthOverride: Float = -1.0 {
    didSet {
      prerenderedEnvironment?.debugMistDepthOverride = mistDepthOverride
    }
  }

  @Editor(-1.0...10.0) var mistStartOverride: Float = -1.0 {
    didSet {
      prerenderedEnvironment?.debugMistStartOverride = mistStartOverride
    }
  }

  @Editor func shakeScreen() { ScreenShake.shared.shake(.subtle) }
  @Editor func shakeScreenMore() { ScreenShake.shared.shake(.heavy) }
  @Editor func shakeScreenVertically() { ScreenShake.shared.shake(.subtle, axis: .vertical) }

  // Scene
  private(set) var scene: Scene?

  // Camera access (delegated to CameraSystem)
  private var camera: Assimp.Camera? { cameraSystem.camera }
  private var cameraWorldTransform: mat4 { cameraSystem.cameraWorldTransform }

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
  var selectedCamera: String {
    get { cameraSystem.selectedCamera }
    set { cameraSystem.selectedCamera = newValue }
  }

  // Main menu system
  private let mainMenu: MainMenu
  private var showingMainMenu: Bool = false

  // Pickup view system
  private var pickupView: PickupView?
  private var showingPickupView: Bool = false

  // Pause screen system
  private let pauseScreenStack: PauseScreenStack
  private var showingPauseScreen: Bool = false

  // Death screen system
  private let deathScreenStack: DeathScreenStack
  private var showingDeathScreen: Bool = false

  // Title screen system
  private let titleScreenStack: TitleScreenStack
  private var showingTitleScreen: Bool = false

  // Dialog system
  private(set) var dialogView: DialogView!
  // Persisted scene flags
  let flagStore = ScriptFlagStore()
  // Scene script instance
  private var sceneScript: Script?

  // Gamepad support
  private var activeGamepad: Gamepad? {
    Gamepad.allGamepads.first
  }
  // Track previous gamepad button states to detect presses (not holds)
  private var buttonPressDetector = GamepadButtonPressDetector()
  // Track which input source was used last (for prompt switching)
  private var lastInputSource: InputSource = .keyboardMouse

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

    // Initialize pause screen
    pauseScreenStack = PauseScreenStack()

    // Initialize death screen
    deathScreenStack = DeathScreenStack()

    // Initialize title screen (not shown by default)
    titleScreenStack = TitleScreenStack()

    // Initialize systems (order matters - physicsWorld must be first)
    physicsWorld = PhysicsWorld(renderLoop: self)
    cameraSystem = CameraSystem()
    playerController = PlayerController(physicsWorld: physicsWorld)
    // InteractionSystem needs all three systems, so create it last
    interactionSystem = InteractionSystem(
      physicsWorld: physicsWorld,
      playerController: playerController,
      cameraSystem: cameraSystem
    )
    // EnemySystem needs physicsWorld and playerController
    enemySystem = EnemySystem(physicsWorld: physicsWorld, playerController: playerController)

    // Initialize weapon system (needs physicsWorld, enemySystem, cameraSystem, playerController)
    weaponSystem = WeaponSystem(
      inventory: Inventory.player1,
      slotGrid: mainMenu.inventoryView.slotGrid,
      physicsWorld: physicsWorld,
      enemySystem: enemySystem,
      cameraSystem: cameraSystem,
      playerController: playerController
    )

    // Register all scene scripts (auto-generated by build tool)
    // This registers factory functions - they'll be called lazily when scripts are created
    registerAllSceneScripts()

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
        let worldTransform = lightNode.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
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

  /// Load foreground meshes from nodes with @Foreground hint
  private func loadForegroundMeshes(scene: Scene) {
    foregroundMeshInstances.removeAll()

    // Use scene.foregroundNodes instead of manual traversal
    for node in scene.foregroundNodes {
      let name = node.name

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

    logger.trace("✅ Loaded \(foregroundMeshInstances.count) foreground mesh instances")
  }

  /// Extract enemy spawn points from @Enemy nodes in the scene
  private func extractEnemySpawnPoints(from scene: Scene) -> [EnemySpawnPoint] {
    var spawnPoints: [EnemySpawnPoint] = []

    // Use scene.enemyNodes instead of manual traversal
    for node in scene.enemyNodes {
      let nodeName = node.name

      // Extract enemy type from base name (e.g., "@Enemy Civilian", "@Enemy Dog.001")
      let baseName = Scene.extractBaseName(from: nodeName)

      // Remove any numeric suffix (e.g., ".001", ".002") for type matching
      let baseTypeName: String
      if let dotIndex = baseName.firstIndex(of: ".") {
        baseTypeName = String(baseName[..<dotIndex])
      } else {
        baseTypeName = baseName
      }

      // Get world transform for position and rotation
      let worldTransform = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
      let position = vec3(worldTransform[3].x, worldTransform[3].y, worldTransform[3].z)

      // Extract forward direction and calculate rotation (same as entry positioning)
      let forward = vec3(worldTransform[2].x, worldTransform[2].y, worldTransform[2].z)
      let yaw = atan2(forward.x, forward.z)
      let rotation = yaw - (.pi * 0.5)

      spawnPoints.append(
        EnemySpawnPoint(
          position: position,
          rotation: rotation,
          typeName: baseTypeName
        ))
    }

    return spawnPoints
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
    cameraSystem.syncActiveCamera(name: name)
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

  // MARK: Input

  /// Handle gamepad button presses (called each frame in update)
  private func handleGamepadButtonPresses(window: Window) {
    guard let gamepad = activeGamepad else { return }
    guard Input.player1.isEnabled else { return }

    // Check all gamepad buttons for press events
    let buttonsToCheck: [Gamepad.Button] = [
      .a, .b, .x, .y, .start, .back, .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
    ]

    let newlyPressed = buttonPressDetector.update(from: gamepad, buttons: buttonsToCheck)

    for button in newlyPressed {
      // Update input source when gamepad button is pressed
      InputSource.updateFromGamepad(gamepad)
      handleGamepadButtonPress(button: button, window: window)
    }
  }

  /// Handle a single gamepad button press
  private func handleGamepadButtonPress(button: Gamepad.Button, window: Window) {
    // Handle different UI states
    if showingTitleScreen {
      // Handle B button for back navigation in title screen
      if button == .b || button == .back {
        if titleScreenStack.handleGamepadButton(button) {
          InputSource.updateFromGamepad(activeGamepad!)
          UISound.cancel()
        }
      }
      return
    }

    if showingPickupView {
      // Forward gamepad input to pickup view
      if let pickupView = pickupView, let gamepad = activeGamepad {
        pickupView.handleGamepadButton(button, gamepad: gamepad)
      }
      return
    }

    if showingPauseScreen {
      if pauseScreenStack.isFadingOut {
        return
      }
      // Handle pause screen back navigation
      if button == .b || button == .back {
        if pauseScreenStack.isAtRoot {
          UISound.cancel()
          hidePauseScreen()
        } else {
          // Navigate back in pause screen stack (handled by NavigationStack via escape key)
          // The NavigationStack will handle it when escape is pressed
        }
      }
      return
    }

    if showingDeathScreen {
      if deathScreenStack.isFadingOut {
        return
      }
      // Handle B button for back navigation in death screen
      if button == .b || button == .back {
        if deathScreenStack.handleGamepadButton(button) {
          InputSource.updateFromGamepad(activeGamepad!)
          UISound.cancel()
        }
      }
      return
    }

    if showingMainMenu {
      // Handle main menu back navigation
      if button == .b || button == .back {
        if mainMenu.hasNestedViewOpen {
          // Nested views (ItemView, DocumentView) handle their own B button presses
          // MainMenu's handleGamepadButtonPresses will handle closing them
          // We don't need to do anything here
        } else {
          // No nested view open, close the main menu
          InputSource.updateFromGamepad(activeGamepad!)
          UISound.cancel()
          hideMainMenu()
        }
      }
      return
    }

    // Gameplay actions
    // Forward gamepad input to DialogView if dialog is active
    if dialogView.isActive {
      if let gamepad = activeGamepad {
        dialogView.handleGamepadButton(button, gamepad: gamepad)
      }
      return
    }

    guard !cameraSystem.isInCloseup else { return }

    // Map gamepad buttons to gameplay actions
    switch button {
    case .a:
      // A button = Interact (F key equivalent)
      if interactionSystem.detectedActionName != nil {
        interactionSystem.handleInteraction(sceneScript: sceneScript)
      } else if interactionSystem.detectedLedgeName != nil {
        interactionSystem.handleLedgeInteraction()
      }

    case .x:
      // X button = Toggle aim (Space key equivalent, for toggle mode)
      if weaponSystem.usesToggledAiming {
        weaponSystem.toggleAim()
      }

    case .start:
      // Start button = Pause (Escape key equivalent)
      UISound.select()
      showPauseScreen()

    case .y:
      // Y button = Inventory (Tab/I key equivalent)
      guard !cameraSystem.isInCloseup else { return }
      UISound.select()
      showMainMenu(tab: .inventory)

    case .b:
      // B button = Map (M key equivalent)
      guard !cameraSystem.isInCloseup else { return }
      UISound.select()
      showMainMenu(tab: .map)

    default:
      break
    }
  }

  func onKey(window: Window, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier) {
    // Track key releases for DialogView ask mode
    if state == .released {
      dialogView.handleKeyRelease(key: key)
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingTitleScreen {
      titleScreenStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    if showingPickupView {
      // Forward input to pickup view
      pickupView?.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    if showingPauseScreen {
      // Don't process input if we're fading out
      if pauseScreenStack.isFadingOut {
        return
      }
      // Handle escape key to close pause screen (only if at root)
      if key == .escape {
        // Check if NavigationStack is at root - if not, let it handle going back
        if pauseScreenStack.isAtRoot {
          UISound.cancel()
          hidePauseScreen()
          return
        }
      }
      // Forward input to pause screen (including escape if not at root)
      pauseScreenStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
      return
    }

    if showingDeathScreen {
      // Don't process input if we're fading out
      if deathScreenStack.isFadingOut {
        return
      }
      // Forward input to death screen
      deathScreenStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
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
        UISound.cancel()
        hideMainMenu()
        return
      }

      // Handle I, M, and Tab to close main menu (check for nested views first)
      if key == .i || key == .m || key == .tab {
        // If there's a nested view (item/document), let MainMenu handle it first
        if mainMenu.hasNestedViewOpen {
          // Forward to main menu, which will forward to the nested view
          mainMenu.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
          return
        }
        // No nested view, close the main menu
        UISound.cancel()
        hideMainMenu()
        return
      }

      // Forward other input to main menu
      mainMenu.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    } else {
      // Handle ask mode navigation first (a/d keys)
      if dialogView.isActive {
        if dialogView.handleAskModeNavigation(key: key) {
          return  // Navigation handled
        }
      }

      // Handle dialog advancement keys first (these always work)
      // Note: Engine already filters out repeat events, so onKeyPressed only fires for actual presses
      switch key {
      case .f, .enter, .numpadEnter:
        // Handle interaction - either advance dialog or interact with action
        // Dialog advancement keys always work, even when dialog is active
        // Only process on actual key presses, not repeats
        guard !Engine.isKeyRepeat else { return }

        if dialogView.isActive {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk or selected option in ask mode
            //UISound.select()
          } else if dialogView.isFinished {
            // Dialog finished, dismiss it (disables input synchronously)
            dialogView.dismiss()
          }
        } else if !cameraSystem.isInCloseup {
          // No dialog showing, handle interaction with detected action or ledge
          if interactionSystem.detectedActionName != nil {
            // Handle action interaction (takes priority)
            interactionSystem.handleInteraction(sceneScript: sceneScript)
          } else if interactionSystem.detectedLedgeName != nil {
            // Handle ledge interaction (if no action detected)
            interactionSystem.handleLedgeInteraction()
          }
        }
        return

      case .space:
        guard !cameraSystem.isInCloseup else { return }

        // Handle aim mode (Space) - toggle mode only
        if dialogView.isActive {
          // If dialog is showing, try to advance it
          if dialogView.tryAdvance() {
            // Advanced to next page/chunk or selected option in ask mode
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
        // Block inventory during closeups
        guard !cameraSystem.isInCloseup else { return }
        UISound.select()
        showMainMenu(tab: .inventory)

      case .m:
        // Block map during closeups
        guard !cameraSystem.isInCloseup else { return }
        UISound.select()
        showMainMenu(tab: .map)

      case .escape:
        // Exit debug camera override mode if active
        if cameraSystem.isDebugCameraOverrideMode {
          UISound.select()
          cameraSystem.setDebugCameraOverrideMode(false)
        } else {
          // Show pause screen if no other UI is showing and dialog is not active
          if !dialogView.isActive && !cameraSystem.isInCloseup {
            UISound.select()
            showPauseScreen()
          }
        }
        break

      case .semicolon:
        UISound.select()
        // Enter debug camera override mode when manually cycling cameras
        cameraSystem.setDebugCameraOverrideMode(true)
        cameraSystem.cycleToNextCamera()

      case .apostrophe:
        UISound.select()
        // Enter debug camera override mode when manually cycling cameras
        cameraSystem.setDebugCameraOverrideMode(true)
        cameraSystem.cycleToPreviousCamera()

      case .graveAccent:
        UISound.select()
        // Enter debug camera override mode and switch to debug camera
        cameraSystem.setDebugCameraOverrideMode(true)
        cameraSystem.switchToDebugCamera()

      case .r:
        UISound.select()
        // Reset player to first entry
        if let currentScene = scene, let firstEntry = currentScene.entryNodes.first {
          positionPlayerAtEntry(firstEntry.baseName, in: currentScene)
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

      case .backspace:
        UISound.select()
        showDebugText.toggle()

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

    if showingTitleScreen {
      titleScreenStack.onMouseMove(window: window, x: x, y: y)
    } else if showingPickupView {
      pickupView?.onMouseMove(window: window, x: x, y: y)
    } else if showingPauseScreen {
      pauseScreenStack.onMouseMove(window: window, x: x, y: y)
    } else if showingDeathScreen {
      deathScreenStack.onMouseMove(window: window, x: x, y: y)
    } else if showingMainMenu {
      mainMenu.onMouseMove(window: window, x: x, y: y)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingTitleScreen {
      titleScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
    } else if showingPickupView {
      pickupView?.onMouseButton(window: window, button: button, state: state, mods: mods)
    } else if showingPauseScreen {
      pauseScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
    } else if showingDeathScreen {
      deathScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
    } else if showingMainMenu {
      mainMenu.onMouseButton(window: window, button: button, state: state, mods: mods)
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingTitleScreen {
      titleScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if showingPickupView {
      pickupView?.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if showingPauseScreen {
      // Don't process input if we're fading out
      if pauseScreenStack.isFadingOut {
        return
      }
      pauseScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
      return
    }

    if showingDeathScreen {
      // Don't process input if we're fading out
      if deathScreenStack.isFadingOut {
        return
      }
      deathScreenStack.onMouseButtonPressed(window: window, button: button, mods: mods)
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
        UISound.cancel()
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
          // } else {
          //   // No dialog showing, handle interaction with detected action
          //   handleInteraction()
        }
      }
    }
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      // No-op for pickup view
    } else if showingPauseScreen {
      // No-op for pause screen
    } else if showingMainMenu {
      mainMenu.onMouseButtonReleased(window: window, button: button, mods: mods)
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    guard Input.player1.isEnabled else { return }

    if showingPickupView {
      pickupView?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    } else if showingPauseScreen {
      // No-op for pause screen
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

  private func showPauseScreen() {
    showingPauseScreen = true
    pauseScreenStack.onAttach(window: Engine.shared.window)
  }

  func hidePauseScreen() {
    // Start fade-out animation
    pauseScreenStack.startFadeOut()
    // Don't set showingPauseScreen = false yet - let it fade out first
  }

  func showDeathScreen() {
    UISound.death()
    showingDeathScreen = true
    deathScreenStack.onAttach(window: Engine.shared.window)
  }

  func hideDeathScreen() {
    // Start fade-out animation
    deathScreenStack.startFadeOut()
    // Don't set showingDeathScreen = false yet - let it fade out first
  }

  func showTitleScreen() {
    // Hide any other screens first
    showingPauseScreen = false
    showingDeathScreen = false
    showingMainMenu = false
    showingPickupView = false

    showingTitleScreen = true
  }

  func hideTitleScreen() {
    showingTitleScreen = false
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

    // Validate @Ref properties before sceneDidLoad() to catch missing nodes/cameras early
    sceneScript?.validateRefs()

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

  /// Determine the best camera node to activate when loading/transitioning scenes
  private func preferredCameraNodeName(for entry: String, in scene: Scene) -> String? {
    // Extract base name from entry (handles @Entry format)
    let entryBaseName = Scene.extractBaseName(from: entry)

    // Try entry-specific camera first (e.g., "hallway" -> "@Camera hallway_1")
    if !entryBaseName.isEmpty {
      if let cameraNode = scene.cameraNode(named: "\(entryBaseName)_1") {
        return cameraNode.name
      }
    }

    // Try default camera "1"
    if let cameraNode = scene.cameraNode(named: "1") {
      return cameraNode.name
    }

    // Fall back to first available camera node
    if let firstCameraNode = scene.cameraNodes.first {
      return firstCameraNode.name
    }

    return nil
  }

  /// Position player at an entry node
  /// - Parameters:
  ///   - entryName: The entry name (e.g., "@Entry 1", "1" will look for "@Entry 1")
  ///   - scene: The scene to search for the entry in
  private func positionPlayerAtEntry(_ entryName: String, in scene: Scene) {
    // Extract base name from entry (handles @Entry format)
    let entryBaseName = Scene.extractBaseName(from: entryName)

    // Use scene.entryNode(named:) to find the entry
    guard let entryNode = scene.entryNode(named: entryBaseName) else {
      logger.warning("⚠️ Entry node not found: \(entryBaseName)")
      return
    }

    let entryWorld = entryNode.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
    let extractedPosition = vec3(entryWorld[3].x, entryWorld[3].y, entryWorld[3].z)
    let fwd = vec3(entryWorld[2].x, entryWorld[2].y, entryWorld[2].z)
    let yaw = atan2(fwd.x, fwd.z)
    let entryRotation = yaw - (.pi * 0.5)

    // The entry position is at the feet, but character controller uses center position
    // Adjust Y position to account for capsule half-height
    let capsuleHalfHeight: Float = 0.8
    let adjustedPosition = vec3(extractedPosition.x, extractedPosition.y + capsuleHalfHeight, extractedPosition.z)

    // Update player position and rotation via PlayerController
    playerController.setPosition(adjustedPosition, rotation: entryRotation)
    playerController.setSpawn(position: extractedPosition, rotation: entryRotation)  // Keep spawn position at feet for reference

    logger.trace("🚀 Positioned player at \(entryBaseName): \(extractedPosition)")
  }

  /// Initialize ledge states based on entry Y position
  private func initializeLedgeStates(entryY: Float, scene: Scene) {
    for ledgeNode in scene.ledgeNodes {
      let ledgeBaseName = Scene.extractBaseName(from: ledgeNode.name)

      // Find high and low child nodes
      var highNode: Node? = nil
      var lowNode: Node? = nil

      func searchChildren(_ node: Node) {
        for child in node.children {
          if scene.hasHint(child, hint: .ledgeHigh) {
            highNode = child
          } else if scene.hasHint(child, hint: .ledgeLow) {
            lowNode = child
          }
          searchChildren(child)
        }
      }
      searchChildren(ledgeNode)

      // Determine initial state by comparing entry Y to high/low positions
      var highY: Float? = nil
      var lowY: Float? = nil

      if let highNode {
        let highWorldTransform = highNode.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
        highY = highWorldTransform[3].y
      }

      if let lowNode {
        let lowWorldTransform = lowNode.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
        lowY = lowWorldTransform[3].y
      }

      // Determine which is closer to entry Y
      let initialState: LedgeState
      if let highY, let lowY {
        let distanceToHigh = abs(entryY - highY)
        let distanceToLow = abs(entryY - lowY)
        initialState = distanceToHigh < distanceToLow ? .high : .low
      } else if highY != nil {
        initialState = .high
      } else if lowY != nil {
        initialState = .low
      } else {
        // No high/low children found, skip this ledge
        logger.warning("⚠️ Ledge '\(ledgeBaseName)' has no high or low children")
        continue
      }

      // Set initial state (this will enable/disable appropriate collision bodies)
      physicsWorld.setLedgeState(initialState, for: ledgeBaseName)
      logger.trace(
        "🔧 Initialized ledge '\(ledgeBaseName)' to \(initialState == .high ? "high" : "low") (entry Y: \(entryY), high Y: \(highY?.description ?? "nil"), low Y: \(lowY?.description ?? "nil"))"
      )
    }
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
    // - Named areas (like "@Entry hallway"): try "@Camera hallway_1", fall back to "@Camera 1"
    // - Unnamed areas (like "@Entry 1"): try "@Camera 1"
    let entryBaseName = Scene.extractBaseName(from: entry)
    let cameraNodeName: String
    let prerenderedCameraName: String

    // Check if entry base name is just a number (unnamed area)
    if entryBaseName.allSatisfy({ $0.isNumber }) {
      // Unnamed area - just use Camera 1
      if let cameraNode = currentScene.cameraNode(named: "1") {
        cameraNodeName = cameraNode.name
      } else {
        cameraNodeName = "@Camera 1"
      }
      prerenderedCameraName = entryBaseName
    } else {
      // Named area - try "@Camera {area}_1", fall back to "@Camera 1"
      if let cameraNode = currentScene.cameraNode(named: "\(entryBaseName)_1") {
        cameraNodeName = cameraNode.name
        prerenderedCameraName = "\(entryBaseName)_1"
      } else if let cameraNode = currentScene.cameraNode(named: "1") {
        cameraNodeName = cameraNode.name
        prerenderedCameraName = "1"
      } else {
        cameraNodeName = "@Camera 1"
        prerenderedCameraName = "1"
      }
    }

    // Switch 3D camera
    cameraSystem.syncActiveCamera(name: cameraNodeName)

    // Switch prerendered environment camera
    try? prerenderedEnvironment?.switchToCamera(prerenderedCameraName)
    cameraSystem.selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? prerenderedCameraName

    // Reset area tracking - actual area is determined by camera triggers
    currentAreaName = nil
    needsInitialCameraTriggerSync = true

    await Task.sleep(0.15)

    // Fade in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Play door close sound after fading in
    UISound.doorCloseA()
  }

  /// Transition to a different scene
  /// - Parameters:
  ///   - scene: The scene name to load
  ///   - entry: Optional entry name (defaults to "1" if not specified)
  @MainActor func transition(toScene scene: String, entry: String? = nil) async {
    // Play door open sound before fading out
    UISound.doorOpenA()

    // Fade out
    await ScreenFade.shared.fadeToBlack(duration: 0.3)

    // Load the new scene and position at entry (defaults to "1" if not specified)
    let entryName = entry ?? "1"

    // Determine prerendered camera name based on entry (same logic as transition(to:))
    // We need to determine this before loading the scene, but we'll need the scene to check for named cameras
    // So we'll load with a default and update if needed
    // Note: We can't use scene.extractBaseName yet since scene isn't loaded, so we'll handle this after loading
    let defaultPrerenderedCameraName: String = "1"

    // Load the scene
    await loadScene(scene, entry: entryName, prerenderedCameraName: defaultPrerenderedCameraName)

    // If it's a named area, check if we need to update the camera
    if let currentScene = self.scene {
      let entryBaseName = Scene.extractBaseName(from: entryName)
      // Check if entry base name is not just a number (named area)
      if !entryBaseName.allSatisfy({ $0.isNumber }),
        let cameraNode = currentScene.cameraNode(named: "\(entryBaseName)_1")
      {
        let prerenderedCameraName = "\(entryBaseName)_1"
        try? prerenderedEnvironment?.switchToCamera(prerenderedCameraName)
        cameraSystem.selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? prerenderedCameraName
        cameraSystem.syncActiveCamera(name: cameraNode.name)
      }
    }

    await Task.sleep(0.15)

    // Fade in
    await ScreenFade.shared.fadeFromBlack(duration: 0.3)

    // Play door close sound after fading in
    UISound.doorCloseA()
  }

  /// Load a scene by name, setting up everything (scene, physics, prerendered environment, player position)
  /// - Parameters:
  ///   - sceneName: The scene name to load
  ///   - entry: The entry name to position player at (defaults to "1")
  ///   - prerenderedCameraName: Optional camera name for prerendered environment (defaults to "1")
  @MainActor func loadScene(_ sceneName: String, entry: String = "1", prerenderedCameraName: String? = nil) async {
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

      // Print debug description of all game-related nodes
      logger.trace("📋 Scene loaded: \(sceneName)")
      // Print each line separately for better readability
      print(scene.debugDescription)

      // Set the scene
      self.scene = scene

      // Validate footsteps nodes - check that all base names match FootstepSound enum cases
      for footstepsNode in scene.footstepsNodes {
        let baseName = footstepsNode.baseName
        // Convert to camelCase: first letter lowercase, rest as-is (e.g., "Metal" -> "metal", "ConcreteEcho" -> "concreteEcho")
        let camelCaseName = baseName.prefix(1).lowercased() + baseName.dropFirst()
        // Check if base name matches a FootstepSound enum case
        if camelCaseName != "default",
          FootstepSound(rawValue: camelCaseName) == nil
        {
          fatalError(
            "❌ Invalid footsteps node '\(footstepsNode.name)': base name '\(baseName)' does not match any FootstepSound enum case. Valid cases: default, concrete, concreteEcho, metal, platform"
          )
        }
      }

      //      // Clear old physics bodies if physics system is ready
      //      guard let physicsSystem = physicsSystem else {
      //        logger.error("⚠️ Physics system not ready, cannot load physics for scene '\(sceneName)'")
      //        return
      //      }

      logger.trace("🔄 Loading physics for scene '\(sceneName)'...")

      // Update camera system with new scene (prerenderedEnvironment will be set later)
      cameraSystem.setScene(scene)

      // Clear old physics bodies
      physicsWorld.clearAllBodies()
      playerController.clear()
      enemySystem.clearAll()

      // Load new collision bodies
      physicsWorld.loadCollisionBodies(scene: scene)
      physicsWorld.loadActionBodies(scene: scene)
      physicsWorld.loadTriggerBodies(scene: scene)
      physicsWorld.loadLedgeBodies(scene: scene)
      physicsWorld.optimizeBroadPhase()
      logger.trace("✅ Loaded physics bodies")

      // Position player at entry (updates player position/rotation)
      // This already adjusts for capsule height, so playerPosition is the center position
      positionPlayerAtEntry(entry, in: scene)

      // Initialize ledge states based on entry position
      initializeLedgeStates(entryY: playerPosition.y, scene: scene)

      // Create character controller at the positioned location
      // Use the position that was set by positionPlayerAtEntry (already adjusted for capsule height)
      playerController.create(at: playerPosition, rotation: playerRotation)

      // Mark physics system as ready for updates
      physicsWorld.setReady(true)

      // Load scene script class dynamically
      loadSceneScript()

      // Reset area tracking - camera triggers define actual areas
      currentAreaName = nil
      needsInitialCameraTriggerSync = true

      // Initialize active camera using best available node to avoid missing-camera warnings
      if let preferredCameraName = preferredCameraNodeName(for: entry, in: scene) {
        cameraSystem.syncActiveCamera(name: preferredCameraName)
      } else {
        logger.warning("⚠️ No camera nodes found to sync in scene '\(sceneName)'")
      }

      // Load foreground meshes (nodes with -fg suffix)
      loadForegroundMeshes(scene: scene)

      // Spawn enemies from Enemy_* nodes
      let enemySpawnPoints = extractEnemySpawnPoints(from: scene)
      enemySystem.spawnFromPoints(enemySpawnPoints)

      // Initialize prerendered environment for the scene
      let cameraName = prerenderedCameraName ?? "1"
      do {
        prerenderedEnvironment = try PrerenderedEnvironment(sceneName, cameraName: cameraName)
        // Set initial mist overrides if set
        prerenderedEnvironment?.debugMistDepthOverride = mistDepthOverride
        prerenderedEnvironment?.debugMistStartOverride = mistStartOverride
        // Update camera system with prerendered environment (now that it's created)
        cameraSystem.setPrerenderedEnvironment(prerenderedEnvironment)
        // Sync the selectedCamera property with the actual current camera
        cameraSystem.selectedCamera = prerenderedEnvironment?.getCurrentCameraName() ?? cameraName
        if let currentScene = self.scene {
          let activeCameraName = cameraSystem.selectedCamera
          if !activeCameraName.isEmpty {
            if let cameraNode = currentScene.cameraNode(named: activeCameraName) {
              cameraSystem.syncActiveCamera(name: cameraNode.name)
            }
          }
        }
      } catch {
        logger.error("⚠️ Failed to initialize PrerenderedEnvironment for scene '\(sceneName)': \(error)")
      }

      // Disable small-room clamping for real scene navigation
      restrictMovementToRoom = false
    } catch {
      logger.error("⚠️ Failed to load scene '\(sceneName)': \(error)")
    }
  }

  @MainActor
  func withScriptedCameraOverride<T>(
    on cameraName: String,
    perform: () async throws -> T
  ) async rethrows -> T {
    return try await cameraSystem.withScriptedCameraOverride(on: cameraName, perform: perform)
  }

  @MainActor
  func withScriptedCameraOverride<T>(
    on cameraName: String,
    perform: () throws -> T
  ) rethrows -> T {
    return try cameraSystem.withScriptedCameraOverride(on: cameraName, perform: perform)
  }

  @MainActor
  func withScriptedPlayerOverride<T>(
    position: vec3,
    rotation: Float,
    perform: () async throws -> T
  ) async rethrows -> T {
    // Save current position and rotation
    let savedPosition = playerController.position
    let savedRotation = playerController.rotation

    // Set new position and rotation
    playerController.setPosition(position, rotation: rotation)

    defer {
      // Restore original position and rotation
      playerController.setPosition(savedPosition, rotation: savedRotation)
    }

    return try await perform()
  }

  private func drawEntryArrows(scene: Scene, debugRenderer: DebugRenderer) {
    // Use scene.entryNodes instead of manual traversal
    for node in scene.entryNodes {
      let world = node.assimpNode.calculateWorldTransform(scene: scene.assimpScene)
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
  }

  func update(window: Window, deltaTime: Float) {
    if showingTitleScreen {
      // Update title screen (takes over everything)
      titleScreenStack.update(deltaTime: deltaTime)
    } else if showingPickupView {
      // Update pickup view
      pickupView?.update(window: window, deltaTime: deltaTime)
    } else if showingPauseScreen {
      // Update pause screen
      pauseScreenStack.update(deltaTime: deltaTime)
      // Check if fade-out is complete and actually hide the pause screen
      if pauseScreenStack.isFadeOutComplete {
        showingPauseScreen = false
        pauseScreenStack.onDetach(window: Engine.shared.window)
      }
    } else if showingDeathScreen {
      // Update death screen
      deathScreenStack.update(deltaTime: deltaTime)
      // Check if fade-out is complete and actually hide the death screen
      if deathScreenStack.isFadeOutComplete {
        showingDeathScreen = false
        deathScreenStack.onDetach(window: Engine.shared.window)
      }
    } else if showingMainMenu {
      // Update main menu
      mainMenu.update(window: window, deltaTime: deltaTime)
    }

    // Handle gamepad button presses (always, regardless of UI state)
    handleGamepadButtonPresses(window: window)

    if !showingTitleScreen && !showingPickupView && !showingPauseScreen && !showingDeathScreen && !showingMainMenu {
      // Only handle movement if dialog is not active, not in closeup, and input is enabled
      if !dialogView.isActive && !cameraSystem.isInCloseup && Input.player1.isEnabled {
        // Check which input is being used (check both simultaneously)
        let keyboard = window.keyboard
        let gamepad = activeGamepad

        // Check for keyboard input activity
        let keyboardActive =
          keyboard.state(of: .w) == .pressed || keyboard.state(of: .s) == .pressed
          || keyboard.state(of: .a) == .pressed || keyboard.state(of: .d) == .pressed
          || keyboard.state(of: .up) == .pressed || keyboard.state(of: .down) == .pressed
          || keyboard.state(of: .left) == .pressed || keyboard.state(of: .right) == .pressed

        // Check for gamepad input activity
        var gamepadActive = false
        if let gamepad {
          let deadzone: Float = 0.2
          let leftStickX = abs(gamepad.state(of: .leftX))
          let leftStickY = abs(gamepad.state(of: .leftY))
          gamepadActive =
            gamepad.state(of: .dpadUp) == .pressed || gamepad.state(of: .dpadDown) == .pressed
            || gamepad.state(of: .dpadLeft) == .pressed || gamepad.state(of: .dpadRight) == .pressed
            || leftStickX > deadzone || leftStickY > deadzone
        }

        // Update input source based on which was used last
        if keyboardActive {
          lastInputSource = .keyboardMouse
          InputSource.player1 = .keyboardMouse
        } else if gamepadActive, let gamepad {
          InputSource.updateFromGamepad(gamepad)
          lastInputSource = InputSource.player1
        }

        // Pass both inputs to PlayerController (it will use whichever has input)
        playerController.update(
          keyboard: keyboard,
          gamepad: gamepad,
          deltaTime: deltaTime,
          physicsWorld: physicsWorld,
          isAiming: weaponSystem.isAiming
        )

        // Update interaction system (detect actions/triggers)
        interactionSystem.update(
          sceneScript: sceneScript,
          currentAreaName: currentAreaName
        )

        // Handle weapon system hold mode and firing
        // Update weapon system (for rate of fire timing)
        weaponSystem.update(deltaTime: deltaTime)

        // Update enemy system
        if !disableEnemies {
          enemySystem.update(deltaTime: deltaTime)
        }

        // Handle hold mode for Space (keyboard) or Left Trigger (gamepad)
        // Check both, prefer keyboard if active
        if !weaponSystem.usesToggledAiming {
          let keyboardAiming = window.keyboard.state(of: .space) == .pressed
          let gamepadAiming = activeGamepad?.state(of: .leftTrigger) ?? 0.0 > 0.5
          let isAimingHeld = keyboardAiming || gamepadAiming

          // Update input source based on which is being used
          if keyboardAiming {
            lastInputSource = .keyboardMouse
            InputSource.player1 = .keyboardMouse
          } else if gamepadAiming, let gamepad = activeGamepad {
            InputSource.updateFromGamepad(gamepad)
            lastInputSource = InputSource.player1
          }

          if isAimingHeld {
            // Aim button held - enter ready aim, then aim
            if weaponSystem.currentAimState == .idle {
              weaponSystem.enterReadyAim()
            } else if weaponSystem.currentAimState == .readyAim {
              weaponSystem.enterAim()
            }
          } else {
            // Aim button released - exit aim
            if weaponSystem.currentAimState != .idle {
              weaponSystem.exitAim()
            }
          }
        }

        // Handle firing with Ctrl (keyboard) or Right Trigger (gamepad)
        // Check both, prefer keyboard if active
        let keyboardFiring =
          window.keyboard.state(of: .leftControl) == .pressed || window.keyboard.state(of: .rightControl) == .pressed
        let gamepadFiring = activeGamepad?.state(of: .rightTrigger) ?? 0.0 > 0.5
        let isFiring = keyboardFiring || gamepadFiring

        // Update input source based on which is being used
        if keyboardFiring {
          lastInputSource = .keyboardMouse
          InputSource.player1 = .keyboardMouse
        } else if gamepadFiring, let gamepad = activeGamepad {
          InputSource.updateFromGamepad(gamepad)
          lastInputSource = InputSource.player1
        }

        if isFiring {
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

  func draw() {
    if showingTitleScreen {
      // Draw title screen (takes over everything)
      titleScreenStack.draw()
      return
    }

    if showingPickupView {
      // Draw pickup view
      pickupView?.draw()
    } else if showingMainMenu {
      // Draw main menu
      mainMenu.draw()
    } else {
      // Draw game scene (always, even when paused - pause screen will overlay on top)
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

      // Draw enemy capsules
      if !disableEnemies {
        let aliveEnemies = enemySystem.aliveEnemies
        if !aliveEnemies.isEmpty && !capsuleMeshInstances.isEmpty {
          glEnable(GL_DEPTH_TEST)
          glDepthMask(true)
          glDepthFunc(GL_LEQUAL)

          let lighting = getSceneLighting()
          let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)

          for enemy in aliveEnemies {
            // Create model matrix: translate to enemy position, then rotate around Y axis
            // Offset Y downward so capsule sits on floor (assuming origin is at center)
            var adjustedPosition = enemy.position
            adjustedPosition.y -= capsuleHeightOffset
            var modelMatrix = GLMath.translate(mat4(1), adjustedPosition)
            modelMatrix = GLMath.rotate(modelMatrix, enemy.rotation, vec3(0, 1, 0))

            for meshInstance in capsuleMeshInstances {
              // Combine the mesh's original transform with enemy transform
              let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix

              // Use a slightly different color to distinguish from player (tint red)
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
      physicsWorld.nextFrame()

      if !showingPauseScreen {
        // Update debug renderer camera and draw if enabled
        if let debugRenderer = physicsWorld.getDebugRenderer() {
          currentProjection = projection
          currentView = view

          // Set camera position for debug renderer (extract from view matrix)
          let cameraPosition = vec3(cameraWorld[3].x, cameraWorld[3].y, cameraWorld[3].z)
          debugRenderer.setCameraPosition(RVec3(x: cameraPosition.x, y: cameraPosition.y, z: cameraPosition.z))

          if visualizePhysics {
            debugRenderer.drawMarker(RVec3(x: 0, y: 0, z: 0), color: 0xFFFF00FF, size: 2.0)
            //physicsWorld.drawBodies(debugRenderer: debugRenderer)

            // Draw interaction system debug visualization (trigger check point)
            interactionSystem.drawDebug(debugRenderer: debugRenderer, projection: projection, view: view)

            // Draw sensor box query shape in purple
            let sensorBox = playerController.getSensorBoxTransform()
            let halfExtents = sensorBox.halfExtents
            let pos = sensorBox.position
            let rot = sensorBox.rotation

            // Convert quaternion to rotation matrix
            let q = rot
            let x2 = q.x + q.x
            let y2 = q.y + q.y
            let z2 = q.z + q.z
            let xx = q.x * x2
            let xy = q.x * y2
            let xz = q.x * z2
            let yy = q.y * y2
            let yz = q.y * z2
            let zz = q.z * z2
            let wx = q.w * x2
            let wy = q.w * y2
            let wz = q.w * z2

            let rotMat = mat4(
              1 - (yy + zz), xy + wz, xz - wy, 0,
              xy - wz, 1 - (xx + zz), yz + wx, 0,
              xz + wy, yz - wx, 1 - (xx + yy), 0,
              0, 0, 0, 1
            )

            // Box corners in local space
            let corners: [vec3] = [
              vec3(-halfExtents.x, -halfExtents.y, -halfExtents.z),
              vec3(halfExtents.x, -halfExtents.y, -halfExtents.z),
              vec3(halfExtents.x, halfExtents.y, -halfExtents.z),
              vec3(-halfExtents.x, halfExtents.y, -halfExtents.z),
              vec3(-halfExtents.x, -halfExtents.y, halfExtents.z),
              vec3(halfExtents.x, -halfExtents.y, halfExtents.z),
              vec3(halfExtents.x, halfExtents.y, halfExtents.z),
              vec3(-halfExtents.x, halfExtents.y, halfExtents.z),
            ]

            // Transform corners to world space
            let worldCorners = corners.map { corner in
              let rotated = rotMat * vec4(corner.x, corner.y, corner.z, 1.0)
              return vec3(rotated.x, rotated.y, rotated.z) + pos
            }

            // Draw box edges in purple (0xFF00FFFF = purple in ABGR)
            let edges: [(Int, Int)] = [
              (0, 1), (1, 2), (2, 3), (3, 0),  // Front face
              (4, 5), (5, 6), (6, 7), (7, 4),  // Back face
              (0, 4), (1, 5), (2, 6), (3, 7),  // Connecting edges
            ]

            // Use the debug renderer's drawLine through the implementation
            // We need to access it through the physics world's debug renderer implementation
            if let debugRendererImpl = physicsWorld.getDebugRendererImplementation() {
              for (i, j) in edges {
                let from = worldCorners[i]
                let to = worldCorners[j]
                debugRendererImpl.drawLine(
                  from: RVec3(x: from.x, y: from.y, z: from.z),
                  to: RVec3(x: to.x, y: to.y, z: to.z),
                  color: 0xFFFFFF00  // Cyan in ABGR format
                )
              }
            }

            // Draw ledge sensor box query shape in orange
            let ledgeSensorBox = playerController.getLedgeSensorBoxTransform()
            let ledgeHalfExtents = ledgeSensorBox.halfExtents
            let ledgePos = ledgeSensorBox.position
            let ledgeRot = ledgeSensorBox.rotation

            // Convert quaternion to rotation matrix
            let ledgeQ = ledgeRot
            let ledgeX2 = ledgeQ.x + ledgeQ.x
            let ledgeY2 = ledgeQ.y + ledgeQ.y
            let ledgeZ2 = ledgeQ.z + ledgeQ.z
            let ledgeXX = ledgeQ.x * ledgeX2
            let ledgeXY = ledgeQ.x * ledgeY2
            let ledgeXZ = ledgeQ.x * ledgeZ2
            let ledgeYY = ledgeQ.y * ledgeY2
            let ledgeYZ = ledgeQ.y * ledgeZ2
            let ledgeZZ = ledgeQ.z * ledgeZ2
            let ledgeWX = ledgeQ.w * ledgeX2
            let ledgeWY = ledgeQ.w * ledgeY2
            let ledgeWZ = ledgeQ.w * ledgeZ2

            let ledgeRotMat = mat4(
              1 - (ledgeYY + ledgeZZ), ledgeXY + ledgeWZ, ledgeXZ - ledgeWY, 0,
              ledgeXY - ledgeWZ, 1 - (ledgeXX + ledgeZZ), ledgeYZ + ledgeWX, 0,
              ledgeXZ + ledgeWY, ledgeYZ - ledgeWX, 1 - (ledgeXX + ledgeYY), 0,
              0, 0, 0, 1
            )

            // Box corners in local space
            let ledgeCorners: [vec3] = [
              vec3(-ledgeHalfExtents.x, -ledgeHalfExtents.y, -ledgeHalfExtents.z),
              vec3(ledgeHalfExtents.x, -ledgeHalfExtents.y, -ledgeHalfExtents.z),
              vec3(ledgeHalfExtents.x, ledgeHalfExtents.y, -ledgeHalfExtents.z),
              vec3(-ledgeHalfExtents.x, ledgeHalfExtents.y, -ledgeHalfExtents.z),
              vec3(-ledgeHalfExtents.x, -ledgeHalfExtents.y, ledgeHalfExtents.z),
              vec3(ledgeHalfExtents.x, -ledgeHalfExtents.y, ledgeHalfExtents.z),
              vec3(ledgeHalfExtents.x, ledgeHalfExtents.y, ledgeHalfExtents.z),
              vec3(-ledgeHalfExtents.x, ledgeHalfExtents.y, ledgeHalfExtents.z),
            ]

            // Transform corners to world space
            let ledgeWorldCorners = ledgeCorners.map { corner in
              let rotated = ledgeRotMat * vec4(corner.x, corner.y, corner.z, 1.0)
              return vec3(rotated.x, rotated.y, rotated.z) + ledgePos
            }

            // Draw box edges in orange (0xFF00A5FF = orange in ABGR)
            let ledgeEdges: [(Int, Int)] = [
              (0, 1), (1, 2), (2, 3), (3, 0),  // Front face
              (4, 5), (5, 6), (6, 7), (7, 4),  // Back face
              (0, 4), (1, 5), (2, 6), (3, 7),  // Connecting edges
            ]

            if let debugRendererImpl = physicsWorld.getDebugRendererImplementation() {
              for (i, j) in ledgeEdges {
                let from = ledgeWorldCorners[i]
                let to = ledgeWorldCorners[j]
                debugRendererImpl.drawLine(
                  from: RVec3(x: from.x, y: from.y, z: from.z),
                  to: RVec3(x: to.x, y: to.y, z: to.z),
                  color: 0xFF00A5FF  // Orange in ABGR format
                )
              }
            }

            // // Draw character controllers (player and enemies)
            // // Player character controller
            // if let characterController = playerController.getCharacterController() {
            //   let worldTransform = characterController.getWorldTransform()
            //   // Draw capsule: halfHeight 0.8, radius 0.4
            //   debugRenderer.drawCapsule(
            //     worldTransform,
            //     halfHeightOfCylinder: 0.8,
            //     radius: 0.4,
            //     color: 0xFF00FF00,  // Green for player
            //     castShadow: .off,
            //     drawMode: .wireframe
            //   )
            // }

            // // Enemy character controllers
            // for enemy in enemySystem.aliveEnemies {
            //   if let characterController = enemy.characterController {
            //     let worldTransform = characterController.getWorldTransform()
            //     // Determine capsule size based on enemy type
            //     let (halfHeight, radius): (Float, Float)
            //     if enemy is DogEnemy {
            //       halfHeight = 0.4
            //       radius = 0.25
            //     } else {
            //       halfHeight = 0.8
            //       radius = 0.4
            //     }
            //     // Red for enemies
            //     debugRenderer.drawCapsule(
            //       worldTransform,
            //       halfHeightOfCylinder: halfHeight,
            //       radius: radius,
            //       color: 0xFFFF0000,  // Red for enemies
            //       castShadow: .off,
            //       drawMode: .wireframe
            //     )
            //   }
            // }

            // Draw gun ray if available
            if let rayInfo = weaponSystem.getLastRayInfo() {
              let rayStart = vec3(rayInfo.origin.x, rayInfo.origin.y, rayInfo.origin.z)
              let rayEnd =
                rayStart + vec3(rayInfo.direction.x, rayInfo.direction.y, rayInfo.direction.z) * rayInfo.range
              debugRenderer.drawLine(
                from: rayInfo.origin,
                to: RVec3(x: rayEnd.x, y: rayEnd.y, z: rayEnd.z),
                color: 0xFFFFFF00  // Yellow for gun ray
              )
            }

            // Draw projectile aim line when aiming
            if weaponSystem.isAiming {
              // Use player position and rotation (tank controls, not first-person)
              // Same calculation as melee damage - forward direction from player rotation
              let forwardX = sin(playerRotation)
              let forwardZ = cos(playerRotation)
              let forward = vec3(forwardX, 0, forwardZ)
              let normalizedForward = normalize(forward)

              // Use same weapon height offset as WeaponSystem (chest level)
              let weaponHeightOffset: Float = 0.3
              let weaponPosition = vec3(playerPosition.x, playerPosition.y + weaponHeightOffset, playerPosition.z)

              // Draw line extending 100 meters forward from weapon position
              let rayLength: Float = 100.0
              let rayEnd = weaponPosition + normalizedForward * rayLength

              // Use drawArrow instead of drawLine - arrows render better for directional indicators
              debugRenderer.drawArrow(
                from: RVec3(x: weaponPosition.x, y: weaponPosition.y, z: weaponPosition.z),
                to: RVec3(x: rayEnd.x, y: rayEnd.y, z: rayEnd.z),
                color: 0xFF00FFFF,  // Cyan for projectile aim line
                size: 0.5  // Arrow head size
              )
            }

            // Draw active projectiles
            let projectilePositions = weaponSystem.getActiveProjectilePositions()
            for position in projectilePositions {
              debugRenderer.drawMarker(
                RVec3(x: position.x, y: position.y, z: position.z),
                color: 0xFFFF0000,  // Red for grenades
                size: 0.1  // Small marker size
              )
            }
          }

          // Draw entry arrows using Jolt debug renderer
          if visualizeEntries, let loadedScene = scene {
            drawEntryArrows(scene: loadedScene, debugRenderer: debugRenderer)
          }
        }

        // Debug overlay (top-left)
        if showDebugText {
          drawDebugInfo()
        }

        // Enemy debug overlay (health bars and state labels)
        if showEnemyDebugOverlay && !disableEnemies {
          drawEnemyDebugOverlay(projection: projection, view: view)
        }

        // Draw dialog view (on top of everything)
        GraphicsContext.current?.renderer.withUIContext {
          dialogView.draw()
        }
      }
    }

    // Draw pause screen as overlay on top of game (if showing)
    if showingPauseScreen {
      pauseScreenStack.draw()
    }

    // Draw death screen as overlay on top of game (if showing)
    if showingDeathScreen {
      deathScreenStack.draw()
    }
  }

  private func drawDebugInfo() {
    let cameraDisplayName: String
    if cameraSystem.isDebugCameraOverrideMode {
      cameraDisplayName = "\(selectedCamera) (override)"
    } else {
      cameraDisplayName = selectedCamera
    }

    let cameraDetails: String
    if let camera {
      if camera.horizontalFOV == 0.0 || camera.orthographicWidth > 0.0 {
        let orthoWidth = camera.orthographicWidth > 0.0 ? camera.orthographicWidth : 1.0
        cameraDetails = String(format: "ortho width %.2f", Double(orthoWidth * 2.0))
      } else {
        let horizontalDegrees = camera.horizontalFOV * 180.0 / .pi
        let halfHorizontalFOV = camera.horizontalFOV * 0.5
        let halfWidthTangent = tan(halfHorizontalFOV)
        if halfWidthTangent > 0.0 {
          let sensorWidthMillimeters: Float = 36.0
          let focalLength = sensorWidthMillimeters / (2.0 * halfWidthTangent)
          cameraDetails = String(format: "%.0f mm / %.1f° FOV", Double(focalLength), Double(horizontalDegrees))
        } else {
          cameraDetails = String(format: "%.1f° FOV", Double(horizontalDegrees))
        }
      }
    } else {
      cameraDetails = "FOV unknown"
    }

    let sceneLine: String
    if let areaName = currentAreaName, !areaName.isEmpty {
      sceneLine = "Scene: \(sceneName) (\(areaName))"
    } else {
      sceneLine = "Scene: \(sceneName)"
    }

    var overlayLines = [
      //String(format: "FPS: %.0f", smoothedFPS),
      sceneLine,
      "Camera: \(cameraDisplayName) (\(cameraDetails))",

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

      interactionSystem.detectedActionName != nil
        ? "Actions: \(interactionSystem.detectedActionName!.prefix(1).lowercased() + interactionSystem.detectedActionName!.dropFirst())"
        : "Actions: none",

      interactionSystem.currentTriggers.isEmpty
        ? "Triggers: none"
        : "Triggers: \(interactionSystem.currentTriggers.map { $0.prefix(1).lowercased() + $0.dropFirst() }.joined(separator: ", "))",
    ]

    // Add ledge line if a ledge is detected
    if let detectedLedgeName = interactionSystem.detectedLedgeName {
      let ledgeName = detectedLedgeName.prefix(1).lowercased() + detectedLedgeName.dropFirst()
      let stateString =
        physicsWorld.ledgeState(for: detectedLedgeName).map { $0 == .high ? "high" : "low" } ?? "unknown"
      overlayLines.append("Ledge: \(ledgeName) (\(stateString))")
    }

    // Add camera triggers line if there are any
    if !interactionSystem.currentCameraTriggers.isEmpty {
      // Extract just the number part from camera trigger names (e.g., "Trigger 1" -> "1", "1" -> "1")
      let triggerNames = interactionSystem.currentCameraTriggers.map { baseName in
        // If baseName ends with a number, extract just the number part
        if let lastSpaceIndex = baseName.lastIndex(of: " "),
          let number = Int(String(baseName[baseName.index(after: lastSpaceIndex)...])),
          number > 0
        {
          return String(number)
        }
        // Otherwise, return the baseName as-is
        return baseName
      }
      overlayLines.append("Camera Triggers: \(triggerNames.joined(separator: ", "))")
    }

    // Add footstep sound line if not default
    let currentFootstepSound = playerController.footstepSound
    if currentFootstepSound != .default {
      overlayLines.append("Footsteps: \(currentFootstepSound.rawValue)")
    }

    let overlay = overlayLines.joined(separator: "\n")

    overlay.draw(
      at: Point(20, Engine.viewportSize.height - 20),
      style: .itemDescription.withMonospacedDigits(true),
      anchor: .topLeft
    )
  }

  private func projectToScreen(position: vec3, projection: mat4, view: mat4, viewportSize: Size) -> Point? {
    let worldPos = vec4(position.x, position.y, position.z, 1.0)
    let clipPos = projection * view * worldPos
    guard abs(clipPos.w) > 0.0001 else { return nil }

    let ndcX = clipPos.x / clipPos.w
    let ndcY = clipPos.y / clipPos.w
    guard ndcX.isFinite && ndcY.isFinite else { return nil }

    let halfWidth = viewportSize.width * 0.5
    let halfHeight = viewportSize.height * 0.5
    let screenX = halfWidth + ndcX * halfWidth
    let screenY = halfHeight + ndcY * halfHeight
    return Point(screenX, screenY)
  }

  private func drawEnemyDebugOverlay(projection: mat4, view: mat4) {
    let viewportSize = Engine.viewportSize
    let aliveEnemies = enemySystem.aliveEnemies

    for enemy in aliveEnemies {
      // Position above enemy (adjust Y offset based on enemy type)
      let yOffset: Float = enemy is DogEnemy ? 0.6 : 1.2
      let worldPosition = vec3(enemy.position.x, enemy.position.y + yOffset, enemy.position.z)

      guard
        let screenPoint = projectToScreen(
          position: worldPosition,
          projection: projection,
          view: view,
          viewportSize: viewportSize
        )
      else { continue }

      // Skip if off-screen
      guard screenPoint.x >= -50 && screenPoint.x <= viewportSize.width + 50,
        screenPoint.y >= -50 && screenPoint.y <= viewportSize.height + 50
      else { continue }

      // Draw health bar
      let barWidth: Float = 60.0
      let barHeight: Float = 6.0
      let healthPercent = enemy.health / enemy.maxHealth

      // Background (red/dark)
      let bgRect = Rect(
        x: screenPoint.x - barWidth * 0.5,
        y: screenPoint.y - 20,
        width: barWidth,
        height: barHeight
      )
      bgRect.fill(with: Color(red: 0.3, green: 0.0, blue: 0.0, alpha: 0.8))

      // Health (green)
      let healthWidth = barWidth * healthPercent
      if healthWidth > 0 {
        let healthRect = Rect(
          x: screenPoint.x - barWidth * 0.5,
          y: screenPoint.y - 20,
          width: healthWidth,
          height: barHeight
        )
        healthRect.fill(with: Color(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.9))
      }

      // Border
      bgRect.frame(with: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9), lineWidth: 1.0)

      // State label
      let stateString: String
      switch enemy.state {
      case .idle: stateString = "Idle"
      case .patrolling: stateString = "Patrol"
      case .chasing: stateString = "Chase"
      case .attacking: stateString = "Attack"
      case .dead: stateString = "Dead"
      }

      stateString.draw(
        at: Point(screenPoint.x, screenPoint.y - 35),
        style: .itemDescription.withMonospacedDigits(true),
        anchor: .center
      )
    }
  }

}
