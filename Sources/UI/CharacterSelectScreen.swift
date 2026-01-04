import GLTF

final class CharacterSelectScreen: RenderLoop {
  // UI
  private let listMenu = ListMenu()
  private let promptList = PromptList(.characterSelect)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  
  // Character data
  private struct CharacterData {
    let name: String
    let modelPath: String?
  }
  
  private let characters: [CharacterData] = [
    CharacterData(name: "Amogus", modelPath: "Actors/capsule"),
    CharacterData(name: "Alex", modelPath: "Actors/alex"),
    CharacterData(name: "????", modelPath: nil),
  ]
  
  private var selectedIndex: Int = 0 {
    didSet {
      if selectedIndex != oldValue && selectedIndex < characters.count {
        Task { await loadCurrentCharacter() }
      }
    }
  }
  
  // 3D model rendering
  private var meshInstances: [MeshInstance] = []
  private var isLoading: Bool = false
  private var isLoadingTextures: Bool = false
  private let loadingSpinner = ProgressIndicator()
  private var textureLoadingTask: Task<Void, Never>?
  
  // Scene/Animations
  private var currentScene: Scene?
  private var animationController = AnimationController()
  private var animationOrder: [Int] = []
  private let preferredAnimationOrder: [String] = [
    "Idle",
    "Walk",
    "Run",
  ]
  
  // Camera / lights
  private var camera = CharacterSelectCamera()
  private var light = Light.itemInspection
  private var fillLight = Light.itemInspectionFill
  
  // Enhanced lighting for character presentation
  private var characterLight: Light {
    var enhanced = Light.itemInspection
    enhanced.intensity = 1.2  // Slightly brighter main light
    return enhanced
  }
  
  private var characterFillLight: Light {
    var enhanced = Light.itemInspectionFill
    enhanced.intensity = 0.4  // Softer fill light
    return enhanced
  }
  
  // Debug state
  private var showDebugInfo: Bool = false  // Camera controls only when debug is enabled
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0
  
  init() {
    setupMenu()
    
    // Configure spinner
    loadingSpinner.strokeWidth = 1.0
    loadingSpinner.strokeColor = .black.withAlphaComponent(0.5)
    
    // Load initial character
    Task { await loadCurrentCharacter() }
  }
  
  deinit {
    textureLoadingTask?.cancel()
  }
  
  private func setupMenu() {
    let menuItems = characters.enumerated().map { index, character in
      ListMenu.MenuItem(id: character.name.lowercased(), label: character.name) {
        // Selection is handled by ListMenu's selectedIndex via onSelectionChanged
      }
    }
    
    listMenu.setItems(menuItems)
    listMenu.style = .boxed  // Left-aligned boxed style with focus ring
    listMenu.position = Point(96, 0) // Top left position
    listMenu.spacing = 56  // Tighter spacing for more polished look
    listMenu.itemWidth = 320  // Slightly wider for better visual presence
    listMenu.onSelectionChanged = { [weak self] index in
      guard let self else { return }
      if index != self.selectedIndex {
        self.selectedIndex = index
        // Note: UISound.navigate() is already called by ListMenu, so we don't duplicate it here
      }
    }
    
    // Sync initial selectedIndex with listMenu
    selectedIndex = listMenu.selectedIndex
  }
  
  // MARK: - Loading
  private func loadCurrentCharacter() async {
    // Cancel any previous texture loading
    textureLoadingTask?.cancel()
    textureLoadingTask = nil
    
    await MainActor.run {
      isLoading = true
      isLoadingTextures = false
      loadingSpinner.isVisible = true
      meshInstances.removeAll()
    }
    
    let character = characters[safe: selectedIndex] ?? characters[0]
    
    guard let modelPath = character.modelPath else {
      // No model for this character (e.g., "????")
      await MainActor.run {
        isLoading = false
        loadingSpinner.isVisible = false
        meshInstances = []
        currentScene = nil
      }
      return
    }
    
    do {
      // Load GLTF document
      let scenePath = Bundle.game.path(forResource: modelPath, ofType: "glb")!
      let url = URL(fileURLWithPath: scenePath)
      let gltfDocument = try await GLTFDocument(contentsOf: url)
      
      // Convert to Scene
      let scene = Scene(gltfDocument, filePath: scenePath)
      self.currentScene = scene
      
      // Create mesh instances from scene
      await MainActor.run {
        // Build a map from mesh index to node for proper transform lookup
        var meshToNodeMap: [Int: Node] = [:]
        func buildMeshToNodeMap(node: Node) {
          for meshIndex in node.meshes {
            if meshToNodeMap[meshIndex] == nil {
              meshToNodeMap[meshIndex] = node
            }
          }
          for child in node.children {
            buildMeshToNodeMap(node: child)
          }
        }
        buildMeshToNodeMap(node: scene.rootNode)
        
        // Create mesh instances
        self.meshInstances = scene.meshes
          .enumerated()
          .filter { $0.element.numberOfVertices > 0 }
          .map { (index, mesh) in
            let node = meshToNodeMap[index]
            let transformMatrix = node?.calculateWorldTransform() ?? mat4(1)
            return MeshInstance(sceneData: scene, mesh: mesh, transformMatrix: transformMatrix, sceneIdentifier: modelPath)
          }
      }
      
      // Load textures asynchronously
      if !meshInstances.isEmpty {
        logger.trace("🎨 Loading textures for \(meshInstances.count) meshes in CharacterSelectScreen...")
        await MainActor.run {
          isLoadingTextures = true
        }
        
        if WAIT_FOR_ALL_TEXTURES {
          // Wait for all textures before showing model
          await meshInstances.loadTexturesConcurrently()
          logger.trace("✅ CharacterSelectScreen textures loaded")
          await MainActor.run {
            isLoading = false
            isLoadingTextures = false
            loadingSpinner.isVisible = false
          }
        } else {
          // Show meshes immediately, load textures in background
          await MainActor.run {
            isLoading = false
          }
          let instances = meshInstances
          textureLoadingTask = Task.detached(priority: .userInitiated) { [weak self] in
            await instances.loadTexturesConcurrently()
            guard let self else { return }
            await MainActor.run {
              logger.trace("✅ CharacterSelectScreen textures loaded (background)")
              self.isLoadingTextures = false
              self.loadingSpinner.isVisible = false
            }
          }
          logger.trace("🎨 CharacterSelectScreen textures loading in background...")
        }
      } else {
        await MainActor.run {
          isLoading = false
          loadingSpinner.isVisible = false
        }
      }
      
      await MainActor.run {
        // Setup animations with preferred ordering
        let rawAnimationNames = scene.animations.enumerated().map { idx, animation in
          if let name = animation.name, !name.isEmpty { return name }
          return "Animation \(idx + 1)"
        }
        
        let humanizedNames = rawAnimationNames.map { self.humanizeAnimationName($0) }
        let orderedIndices = self.buildAnimationOrder(from: humanizedNames)
        
        self.animationOrder = orderedIndices
        
        // Play idle animation if available, otherwise play first animation
        if let idleIndex = orderedIndices.first(where: { 
          let name = humanizedNames[$0].lowercased()
          return name.contains("idle")
        }) {
          let animation = scene.animations[idleIndex]
          self.animationController.play(animation: animation)
        } else if let firstIndex = orderedIndices.first {
          let animation = scene.animations[firstIndex]
          self.animationController.play(animation: animation)
        }
      }
    } catch {
      await MainActor.run {
        self.meshInstances = []
        self.currentScene = nil
        self.isLoading = false
        self.loadingSpinner.isVisible = false
      }
      logger.error("Failed to load character: \(modelPath)")
    }
  }
  
  // MARK: - Input
  func update(window: Window, deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
    
    // Update camera
    camera.update(deltaTime: deltaTime)
    
    // Only process camera input when debug mode is enabled
    if showDebugInfo {
      camera.processKeyboardState(window.keyboard, deltaTime)
      
      // Handle gamepad input for camera
      if let gamepad = Gamepad.allGamepads.first {
        camera.processGamepadState(gamepad, deltaTime)
        // Only handle menu navigation if not using camera controls
        let deadzone: Float = 0.1
        let hasCameraInput = abs(gamepad.state(of: .rightX)) > deadzone || 
                             abs(gamepad.state(of: .rightY)) > deadzone ||
                             gamepad.state(of: .rightTrigger) > 0.1 ||
                             gamepad.state(of: .leftTrigger) > 0.1
        if !hasCameraInput {
          listMenu.handleGamepadInput(gamepad, deltaTime: deltaTime)
        }
      }
    } else {
      // Normal menu navigation when debug is off
      if let gamepad = Gamepad.allGamepads.first {
        listMenu.handleGamepadInput(gamepad, deltaTime: deltaTime)
      }
    }
    
    // Update loading spinner
    loadingSpinner.update(deltaTime: deltaTime)
    
    // Update animation controller
    animationController.update(deltaTime: deltaTime)
    
    // Update bone transforms for all mesh instances from shared animation
    let animatedTransforms = animationController.getAnimatedNodeTransforms()
    meshInstances.forEach { $0.updateBoneTransforms(animatedNodeTransforms: animatedTransforms) }
  }
  
  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Toggle debug mode (enables/disables camera controls)
    if key == .backspace {
      showDebugInfo.toggle()
      UISound.select()
      // Stop dragging when toggling debug off
      if !showDebugInfo {
        camera.stopDragging()
      }
      return
    }
    
    // Camera controls (only when debug is enabled)
    if showDebugInfo {
      switch key {
      case .r:
        camera.resetToInitialPosition()
        UISound.select()
        return
      default:
        // Let camera process keyboard input in update()
        break
      }
    }
    
    // Menu navigation
    if listMenu.handleKeyPressed(key) {
      return
    }
    
    // Handle return/back
    if key == .b || key == .escape {
      UISound.cancel()
      // Could navigate back or close screen here
    }
  }
  
  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    // Camera drag controls (only when debug is enabled)
    if showDebugInfo && button == .left {
      if state == .pressed {
        camera.startDragging()
      } else if state == .released {
        camera.stopDragging()
      }
    } else if button == .right && state == .pressed {
      UISound.cancel()
      // Could navigate back or close screen here
    }
  }
  
  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      listMenu.handleMouseClick(at: mousePosition)
    } else if button == .right {
      UISound.cancel()
      // Could navigate back or close screen here
    }
  }
  
  func onMouseMove(window: Window, x: Double, y: Double) {
    // Camera rotation (only when debug is enabled)
    if showDebugInfo {
      let isAltPressed =
        window.keyboard.state(of: .leftAlt) == .pressed || window.keyboard.state(of: .rightAlt) == .pressed
      camera.processMousePosition(Float(x), Float(y), isAltPressed: isAltPressed)
      lastMouseX = x
      lastMouseY = y
    }
    
    // Menu hover
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    listMenu.handleMouseMove(at: mousePosition)
  }
  
  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    // Camera zoom (only when debug is enabled)
    if showDebugInfo {
      camera.processMouseScroll(Float(yOffset))
    }
  }
  
  // MARK: - Draw
  func draw() {
    // Background with refined AAA look
    ambientBackground.draw { shader in
      shader.setVec3("uTintDark", value: (0.02, 0.025, 0.03))  // Darker, more cinematic
      shader.setVec3("uTintLight", value: (0.07, 0.08, 0.09))  // Subtle highlights
      shader.setFloat("uMottle", value: 0.25)  // Less mottling for cleaner look
      shader.setFloat("uGrain", value: 0.05)  // Less grain
      shader.setFloat("uVignette", value: 0.4)  // Slightly stronger vignette
      shader.setFloat("uDust", value: 0.04)  // Less dust
    }
    
    // Draw title "CHARACTER SELECT" at top left with AAA styling
    let titleStyle = TextStyle(
      fontName: "CreatoDisplay-ExtraBold",
      fontSize: 36,
      color: .white,
      shadowWidth: 3,
      shadowOffset: Point(0, -2),
      shadowColor: .black.withAlphaComponent(0.6)
    )
    let viewportHeight = Float(Engine.viewportSize.height)
    let viewportWidth = Float(Engine.viewportSize.width)
    let sidePadding: Float = 96  // Padding from screen edges
    let titleTopMargin: Float = 120  // More space around heading
    let titleY = viewportHeight - titleTopMargin
    let titleX: Float = sidePadding
    
    // Draw title
    "CHARACTER SELECT".draw(
      at: Point(titleX, titleY),
      style: titleStyle,
      anchor: .bottomLeft
    )
    
    // Draw subtle divider line below title - full width with padding
    // In OpenGL: Y=0 is bottom, higher Y = higher on screen
    // To move DOWN, we SUBTRACT from Y
    let dividerSpacing: Float = 40  // More separation between header and menu
    let dividerY = titleY - dividerSpacing  // Move down from title
    let dividerWidth = viewportWidth - (sidePadding * 2)  // Full width minus padding
    let dividerHeight: Float = 1
    let dividerGradient = Gradient(
      colors: [.white.withAlphaComponent(0.2), .white.withAlphaComponent(0.2), .clear],
      locations: [0.0, 0.9, 1.0]
    )
    let divider = Rect(
      x: sidePadding,
      y: dividerY - dividerHeight / 2,  // Center the divider vertically
      width: dividerWidth,
      height: dividerHeight
    )
    divider.fill(with: dividerGradient)
    
    // Draw menu - position it way down below the divider
    // ListMenu uses position.y as menuStartY when position.y != 0
    // Then it calculates: baseY = menuStartY + (count - 1 - index) * spacing
    // So menuStartY is the Y of the TOP item (highest Y)
    // In OpenGL: lower Y = lower on screen, so subtract MORE to move down
    let menuSpacing: Float = 200  // Way way more spacing - move menu way down
    let menuStartY = dividerY - menuSpacing  // Position menu way down below divider
    listMenu.position = Point(sidePadding, menuStartY)
    listMenu.draw()
    
    // Draw 3D character on the right side
    if !meshInstances.isEmpty {
      draw3DCharacter()
      
      // Show loading spinner in bottom-left corner if textures are loading
      if !WAIT_FOR_ALL_TEXTURES && isLoadingTextures {
        let spinnerSize: Float = 32
        let margin: Float = 20
        let spinnerCenter = Point(margin + spinnerSize / 2, margin + spinnerSize / 2)
        loadingSpinner.size = spinnerSize
        loadingSpinner.draw(centeredAt: spinnerCenter)
      }
    } else if isLoading {
      // Show loading spinner in center
      loadingSpinner.draw()
    }
    
    // Draw prompt list with better positioning
    promptList.iconOpacity = 0.7  // Slightly more visible
    promptList.draw()
    
    // Draw debug info if enabled (temporarily always on)
    if showDebugInfo {
      camera.drawDebugInfo()
    }
  }
  
  private func draw3DCharacter() {
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
    let view = camera.getViewMatrix()
    let cameraModelMatrix = camera.getModelMatrix()
    
    meshInstances.forEach { meshInstance in
      // Bone transforms are already calculated in update() for skeletal meshes
      let combinedModelMatrix = cameraModelMatrix * meshInstance.transformMatrix
      
      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: camera.position,
        lightDirection: characterLight.direction,
        lightColor: characterLight.color,
        lightIntensity: characterLight.intensity,
        fillLightDirection: characterFillLight.direction,
        fillLightColor: characterFillLight.color,
        fillLightIntensity: characterFillLight.intensity,
        diffuseOnly: false,
        effectiveRenderMode: meshInstance.renderMode,
        showFinalAlpha: false,
        showClassification: false,
        cutoutThreshold: 0.5,
        renderPassName: "CharacterSelectModel",
        useAlphaHash: meshInstance.useAlphaHash,
        useAlphaToCoverage: true,
        usePolygonOffset: false
      )
    }
  }
  
  // MARK: - Helpers
  
  private func humanizeAnimationName(_ name: String) -> String {
    let replacedSeparators =
      name
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
    
    let spacedCamelCase = replacedSeparators.replacingOccurrences(
      of: #"(?<=[a-z])(?=[A-Z])"#,
      with: " ",
      options: .regularExpression
    )
    
    let trimmed = spacedCamelCase.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Animation" }
    return trimmed.titleCased
  }
  
  private func buildAnimationOrder(from names: [String]) -> [Int] {
    var orderedIndices: [Int] = []
    var used: Set<Int> = []
    let preferredLower = preferredAnimationOrder.map { $0.lowercased() }
    
    for preferred in preferredLower {
      if let match = names.enumerated().first(where: { $0.element.lowercased() == preferred }) {
        orderedIndices.append(match.offset)
        used.insert(match.offset)
      }
    }
    
    let remaining = names.enumerated()
      .filter { !used.contains($0.offset) }
      .sorted { $0.element.localizedCaseInsensitiveCompare($1.element) == .orderedAscending }
      .map { $0.offset }
    
    orderedIndices.append(contentsOf: remaining)
    return orderedIndices
  }
}

// Custom camera for CharacterSelectScreen - positioned to show character on right side
class CharacterSelectCamera: ItemInspectionCamera {
  /// Initialize with defaults optimized for character viewing on right side
  override init(
    target: vec3 = vec3(0.0, 0.85, 0.0),  // Base target position
    distance: Float = 1.2,  // Distance from debug info
    modelYaw: Float = -14.0,  // Yaw from debug info
    modelPitch: Float = 0.0  // Pitch (default)
  ) {
    super.init(target: target, distance: distance, modelYaw: modelYaw, modelPitch: modelPitch)
    // Set pan offset to match debug info
    panOffset = vec3(-0.13, 0.8, 0.0)
    // Apply pan offset to target
    self.target = target + panOffset
    // Parent class will handle update() - it already has all the momentum/physics logic
  }
}
