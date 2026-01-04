import GLTF

@Editable
final class ModelViewer: RenderLoop {
  // UI
  private let promptList = PromptList(.modelViewer)
  private let secondaryPromptList = PromptList(.modelViewerControls, axis: .vertical)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // Button prompts for model and animation navigation
  private let prevModelPrompt = Prompt([["keyboard_q"], ["xbox_lb"], ["playstation_trigger_l1"]])
  private let nextModelPrompt = Prompt([["keyboard_e"], ["xbox_rb"], ["playstation_trigger_r1"]])
  private let prevAnimationPrompt = Prompt([["keyboard_1"], ["xbox_dpad_up"], ["playstation_dpad_up"]])
  private let nextAnimationPrompt = Prompt([["keyboard_3"], ["xbox_dpad_down"], ["playstation_dpad_down"]])

  // Models
  private let modelPaths: [String] = [
    "Actors/woman01",
    "Actors/alex",
    //"Actors/goth_girl",
    //"Actors/guard",
    "Actors/marit",
    //"Actors/rat",
  ]
  private var currentModelIndex: Int = 0
  private var meshInstances: [MeshInstance] = []
  private var isLoading: Bool = false
  private var isLoadingTextures: Bool = false
  private let loadingSpinner = ProgressIndicator()
  private var textureLoadingTask: Task<Void, Never>?

  // Scene/Animations
  private var currentAnimationNames: [String] = []
  private var animationOrder: [Int] = []
  private var currentAnimationIndex: Int = 0
  private var currentScene: Scene?
  private var animationController = AnimationController()
  private let preferredAnimationOrder: [String] = [
    "Idle",
    "Walk",
    "Run",
  ]

  // Camera / lights
  private var camera = ModelViewerCamera()
  private var light = Light.itemInspection
  private var fillLight = Light.itemInspectionFill

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // UI visibility toggle
  private var showControls: Bool = true
  
  // Debug state
  private var showDebugInfo: Bool = false
  @Editor private var useDiffuseOnly: Bool = false
  @Editor private var showTextureDebug: Bool = false  // Output baseColorTexture.rgb in opaque pass
  @Editor private var showUVDebug: Bool = false  // Output fract(uv) for UV visualization
  @Editor private var showUVRaw: Bool = false  // Output raw uv for UV visualization
  
  // Simplified transparency debug system
  // Store as simple String - will be manually added to getEditableProperties() with picker options
  private var transparencyDebugMode: String = "Normal"  // One control determines all transparency behavior
  
  // Two debug visualizations only
  @Editor private var showFinalAlpha: Bool = false  // Output finalAlpha as grayscale
  @Editor private var showClassification: Bool = false  // Flat colors by renderMode: Opaque=gray, OverlayBlend=cyan, CutoutCoverage=magenta, TrueBlend=yellow
  
  // CutoutCoverage threshold (only relevant when mode is ForceCutoutCoverage or Normal+renderMode==CutoutCoverage)
  @Editor(0.0...1.0) private var cutoutThreshold: Float = 0.5  // Cutout threshold for CutoutCoverage mode

  // Layout tuning
  @Editor(200...500) var controlsPanelWidth: Float = 320
  @Editor(50...500) var controlsTopMargin: Float = 200
  @Editor(5...20) var controlsHeaderSpacing: Float = 10
  @Editor(16...32) var controlsHeaderFontSize: Float = 24
  @Editor(256...1024) var controlsDividerWidth: Float = 384
  @Editor(1...5) var controlsDividerHeight: Float = 2

  @Editor(100...300) var modelNameBaseline: Float = 160
  @Editor(100...300) var animationNameBaseline: Float = 128
  @Editor(200...500) var promptAreaWidth: Float = 400
  @Editor(0.1...0.9) var promptHorizontalFactor: Float = 0.36
  @Editor(5...20) var modelPromptVerticalOffset: Float = 8
  @Editor(5...20) var animationPromptVerticalOffset: Float = 8
  @Editor(256...1024) var modelNameDividerWidth: Float = 512
  @Editor(1...5) var modelNameDividerHeight: Float = 2

  init() {
    // Configure spinner with stroke
    loadingSpinner.strokeWidth = 1.0
    loadingSpinner.strokeColor = .black.withAlphaComponent(0.5)
    
    Task { await loadCurrentModel() }
  }
  
  deinit {
    textureLoadingTask?.cancel()
  }

  // MARK: - Loading
  private func loadCurrentModel() async {
    // Cancel any previous texture loading
    textureLoadingTask?.cancel()
    textureLoadingTask = nil
    
    await MainActor.run {
      isLoading = true
      isLoadingTextures = false
      loadingSpinner.isVisible = true
      meshInstances.removeAll()
      currentAnimationNames.removeAll()
    }

    let path = modelPaths[safe: currentModelIndex] ?? modelPaths[0]
    do {
      // Load GLTF document
      let scenePath = Bundle.game.path(forResource: path, ofType: "glb")!
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
            return MeshInstance(sceneData: scene, mesh: mesh, transformMatrix: transformMatrix, sceneIdentifier: path)
          }
      }
      
      // Load textures asynchronously for all mesh instances
      if !meshInstances.isEmpty {
        logger.trace("🎨 Loading textures for \(meshInstances.count) meshes in ModelViewer...")
        await MainActor.run {
          isLoadingTextures = true
        }
        
        if WAIT_FOR_ALL_TEXTURES {
          // Wait for all textures before showing model
          await meshInstances.loadTexturesConcurrently()
          logger.trace("✅ ModelViewer textures loaded")
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
              logger.trace("✅ ModelViewer textures loaded (background)")
              self.isLoadingTextures = false
              self.loadingSpinner.isVisible = false
            }
          }
          logger.trace("🎨 ModelViewer textures loading in background...")
        }
      } else {
        await MainActor.run {
          isLoading = false
          loadingSpinner.isVisible = false
        }
      }
      
      await MainActor.run {
        // Setup animations with preferred ordering and humanized names
        let rawAnimationNames = scene.animations.enumerated().map { idx, animation in
          if let name = animation.name, !name.isEmpty { return name }
          return "Animation \(idx + 1)"
        }

        let humanizedNames = rawAnimationNames.map { self.humanizeAnimationName($0) }
        let orderedIndices = self.buildAnimationOrder(from: humanizedNames)

        self.animationOrder = orderedIndices
        self.currentAnimationNames = orderedIndices.compactMap { humanizedNames[safe: $0] }
        self.currentAnimationIndex = 0
        self.playCurrentAnimation()
      }
    } catch {
      await MainActor.run {
        self.meshInstances = []
        self.currentAnimationNames = []
        self.animationOrder = []
        self.isLoading = false
        self.loadingSpinner.isVisible = false
      }
      logger.error("Failed to load: \(path)")
    }
  }

  // MARK: - Input
  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if button == .left {
      if state == .pressed { camera.startDragging() } else if state == .released { camera.stopDragging() }
    } else if button == .right && state == .pressed {
      // Placeholder close action for now
      UISound.cancel()
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    let isAltPressed =
      window.keyboard.state(of: .leftAlt) == .pressed || window.keyboard.state(of: .rightAlt) == .pressed
    camera.processMousePosition(Float(x), Float(y), isAltPressed: isAltPressed)
    lastMouseX = x
    lastMouseY = y
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .q:
      previousModel()
    case .e:
      nextModel()
    case .r:
      camera.resetToInitialPosition()
    case .z:
      showControls.toggle()
      UISound.select()
    case .up:
      previousAnimation()
    case .down:
      nextAnimation()
    case .space:
      toggleAnimation()
    case .num1:
      previousAnimation()
    case .num3:
      nextAnimation()
    case .backspace:
      UISound.select()
      showDebugInfo.toggle()
    case .period:
      UISound.select()
      useDiffuseOnly.toggle()
    case .comma:
      UISound.select()
      showTextureDebug.toggle()
    case .slash:
      // Removed debugCutoutStep - use showFinalAlpha and showClassification instead
      break
    default:
      break
    }
  }

  // MARK: - Gamepad Button Handling
  /// Handle gamepad button presses for ModelViewer
  func handleGamepadButton(_ button: Gamepad.Button, gamepad: Gamepad) {
    InputSource.updateFromGamepad(gamepad)

    switch button {
    case .b:
      // B button = Close (right-click equivalent)
      // Note: ModelViewer doesn't have a close callback, this might be handled by parent
      break
    case .x:
      // X button = Reset camera (R key equivalent)
      camera.resetToInitialPosition()
      UISound.select()
    case .dpadUp:
      // D-pad up = Previous animation (Up key equivalent)
      previousAnimation()
    case .dpadDown:
      // D-pad down = Next animation (Down key equivalent)
      nextAnimation()
    case .y:
      // Y button = Toggle animation (Space key equivalent)
      toggleAnimation()
    case .leftBumper:
      // Left bumper = Previous model (Q key equivalent)
      previousModel()
    case .rightBumper:
      // Right bumper = Next model (E key equivalent)
      nextModel()
    default:
      break
    }
  }

  private func nextModel() {
    currentModelIndex = (currentModelIndex + 1) % modelPaths.count
    UISound.select()
    Task { await loadCurrentModel() }
  }

  private func previousModel() {
    currentModelIndex = (currentModelIndex - 1 + modelPaths.count) % modelPaths.count
    UISound.select()
    Task { await loadCurrentModel() }
  }

  private func nextAnimation() {
    guard !currentAnimationNames.isEmpty else { return }
    currentAnimationIndex = (currentAnimationIndex + 1) % currentAnimationNames.count
    playCurrentAnimation()
    UISound.select()
  }

  private func previousAnimation() {
    guard !currentAnimationNames.isEmpty else { return }
    currentAnimationIndex = (currentAnimationIndex - 1 + currentAnimationNames.count) % currentAnimationNames.count
    playCurrentAnimation()
    UISound.select()
  }

  private func playCurrentAnimation() {
    guard let sceneData = currentScene,
      currentAnimationIndex < currentAnimationNames.count
    else {
      logger.warning(
        "ModelViewer: Cannot play animation - scene: \(currentScene != nil), index: \(currentAnimationIndex), count: \(currentScene?.animations.count ?? 0)"
      )
      return
    }

    let orderedIndex = animationOrder[safe: currentAnimationIndex] ?? currentAnimationIndex
    guard orderedIndex < sceneData.animations.count else {
      logger.warning(
        "ModelViewer: Animation order out of bounds - orderedIndex: \(orderedIndex), count: \(sceneData.animations.count)"
      )
      return
    }

    let animation = sceneData.animations[orderedIndex]
    logger.trace(
      "ModelViewer: Playing animation \(currentAnimationIndex): '\(currentAnimationNames[safe: currentAnimationIndex] ?? "Unknown")'"
    )
    logger.trace("  Animation duration: \(animation.duration), tps: \(animation.ticksPerSecond)")
    logger.trace("  Animation channels: \(animation.channels.count)")
    for (idx, channel) in animation.channels.prefix(5).enumerated() {
      logger.trace(
        "    Channel \(idx): node='\(channel.nodeName)', posKeys=\(channel.positionKeys.count), rotKeys=\(channel.rotationKeys.count), scaleKeys=\(channel.scalingKeys.count)"
      )
    }

    // Check mesh bone counts
    logger.trace("  Mesh instances: \(meshInstances.count)")
    for (idx, instance) in meshInstances.enumerated() {
      logger.trace(
        "    Mesh \(idx): bones=\(instance.mesh.numberOfBones), isSkeletal=\(instance.mesh.numberOfBones > 0)")
    }

    // Play animation on shared controller
    animationController.play(animation: animation)
  }

  private func toggleAnimation() {
    if animationController.playing {
      animationController.pause()
    } else {
      animationController.resume()
    }
    UISound.select()
  }

  // MARK: - Update
  func update(window: Window, deltaTime: Float) {
    camera.update(deltaTime: deltaTime)
    camera.processKeyboardState(window.keyboard, deltaTime)

    // Handle gamepad input for camera rotation and zoom
    if let gamepad = Gamepad.allGamepads.first {
      camera.processGamepadState(gamepad, deltaTime)
    }

    // Update loading spinner
    // Always update (handles fade animation)
    loadingSpinner.update(deltaTime: deltaTime)

    // Update shared animation controller
    animationController.update(deltaTime: deltaTime)

    // Update bone transforms for all mesh instances from shared animation
    let animatedTransforms = animationController.getAnimatedNodeTransforms()
    meshInstances.forEach { $0.updateBoneTransforms(animatedNodeTransforms: animatedTransforms) }

    // Debug: Print animation status every 2 seconds
    if Int(animationController.time) % 2 == 0 && animationController.playing {
      logger.trace(
        "ModelViewer: Animation playing - time: \(animationController.time)"
      )
    }
  }

  // MARK: - Draw
  func draw() {
    // Background
    ambientBackground.draw { shader in
      shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
      shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
      shader.setFloat("uMottle", value: 0.35)
      shader.setFloat("uGrain", value: 0.08)
      shader.setFloat("uVignette", value: 0.35)
      shader.setFloat("uDust", value: 0.06)
    }

    if !meshInstances.isEmpty {
      draw3DModel()
      
      // Show loading spinner in bottom-left corner (with fade animation)
      if !WAIT_FOR_ALL_TEXTURES {
        let spinnerSize: Float = 32
        let margin: Float = 20
        let spinnerCenter = Point(margin + spinnerSize / 2, margin + spinnerSize / 2)
        loadingSpinner.size = spinnerSize
        loadingSpinner.draw(centeredAt: spinnerCenter)
      }
    } else if isLoading {
      // Show loading spinner in center (waiting for mesh creation)
      loadingSpinner.draw()
    }

    if showControls {
      drawModelName()

      // Prompt lists
      promptList.group = .modelViewer
      promptList.draw()

      if let prompts = PromptGroup.prompts[.modelViewerControls] {
        let viewportHeight = Float(Engine.viewportSize.height)
        let originX = Float(Engine.viewportSize.width) - controlsPanelWidth

        // Calculate prompt list size and header height
        let headerStyle = TextStyle(
          fontName: "CreatoDisplay-Bold",
          fontSize: controlsHeaderFontSize,
          color: .white
        )
        //let headerHeight = "Controls".size(with: headerStyle).height
        let headerSpacing = controlsHeaderSpacing
        let dividerHeight = controlsDividerHeight

        // Position from top of screen (higher Y = higher on screen in OpenGL)
        // In OpenGL, Y=0 is at bottom, viewportHeight is at top
        // Position near top with some margin
        let topMargin = controlsTopMargin
        let headerTopY = viewportHeight - topMargin

        // Draw "Controls" header first (at the top)
        "Controls".draw(
          at: Point(originX + 5, headerTopY),
          style: headerStyle,
          anchor: .bottomLeft
        )

        // Draw divider below the header
        let headerBottomY = headerTopY - headerSpacing
        let dividerGradient = Gradient(colors: [.clear, .white.withAlphaComponent(0.15)], locations: [0.0, 0.1])
        let dividerWidth = controlsDividerWidth
        let dividerX = Engine.viewportSize.width - dividerWidth
        let dividerY = headerBottomY
        let divider = Rect(x: dividerX, y: dividerY - dividerHeight / 2, width: dividerWidth, height: dividerHeight)
        divider.fill(with: dividerGradient)

        // Draw prompt list below the divider (lower Y = lower on screen)
        let promptListTopY = headerBottomY - headerSpacing
        let promptListOrigin = Point(originX, promptListTopY)
        //Rect(origin: promptListOrigin, size: Size(10, 10)).frame(with: .red)
        secondaryPromptList.iconOpacity = 0.6
        secondaryPromptList.draw(
          prompts: prompts,
          inputSource: .player1,
          origin: promptListOrigin,
          anchor: .topLeft
        )
      }
    }
    
    // Draw debug info if enabled
    if showDebugInfo {
      camera.drawDebugInfo()
    }
  }

  private func draw3DModel() {
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
    let view = camera.getViewMatrix()
    let cameraModelMatrix = camera.getModelMatrix()

    // Separate opaque and transparent meshes for proper alpha blending
    let cameraPosition = camera.position
    var opaqueMeshes: [(instance: MeshInstance, matrix: mat4, effectiveRenderMode: MeshInstance.RenderMode, useAlphaHash: Bool, useAlphaToCoverage: Bool, usePolygonOffset: Bool)] = []
    var transparentMeshes: [(instance: MeshInstance, matrix: mat4, distance: Float, effectiveRenderMode: MeshInstance.RenderMode, useAlphaHash: Bool, useAlphaToCoverage: Bool, usePolygonOffset: Bool)] = []

    for meshInstance in meshInstances {
      let combinedModelMatrix = cameraModelMatrix * meshInstance.transformMatrix
      
      // Extract world position from transform matrix (translation is in column 3)
      let worldPosition = vec3(
        combinedModelMatrix[3].x,
        combinedModelMatrix[3].y,
        combinedModelMatrix[3].z
      )
      
      // Calculate distance from camera for sorting
      let distance = length(worldPosition - cameraPosition)
      
      // Compute effective renderMode and flags based on transparencyDebugMode
      let effectiveRenderMode = computeEffectiveRenderMode(actualRenderMode: meshInstance.renderMode)
      let (useAlphaHash, useAlphaToCoverage, usePolygonOffset) = computeEffectiveFlags(
        transparencyDebugMode: transparencyDebugMode,
        effectiveRenderMode: effectiveRenderMode,
        actualUseAlphaHash: meshInstance.useAlphaHash
      )
      
      // Separate meshes by effective render mode (may be overridden by transparencyDebugMode):
      // - Opaque: render in opaque pass (no blending, depth write ON)
      // - CutoutCoverage: render in opaque pass with alpha-to-coverage or discard (no blending, depth write ON)
      //   This avoids transparent self-occlusion between overlapping alpha cards
      // - OverlayBlend: render in transparent pass (sorted, depth write OFF, blending ON, no dither/cutoff)
      // - Translucent: render in transparent pass (sorted, depth write OFF)
      let needsTransparentPass: Bool
      switch effectiveRenderMode {
      case .opaque, .cutoutCoverage:
        // Opaque and CutoutCoverage: render in opaque pass
        needsTransparentPass = false
      case .overlayBlend, .translucent:
        // OverlayBlend and Translucent: always render in transparent pass
        needsTransparentPass = true
      }
      
      if needsTransparentPass {
        transparentMeshes.append((meshInstance, combinedModelMatrix, distance, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset))
      } else {
        opaqueMeshes.append((meshInstance, combinedModelMatrix, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset))
      }
    }

    // Count meshes by render mode and log material names for debugging (one-frame snapshot)
    var opaqueCount = 0
    var cutoutCoverageCount = 0
    var overlayBlendCount = 0
    var trueBlendCount = 0
    var opaqueMaterials: [String] = []
    var cutoutMaterials: [String] = []
    var overlayMaterials: [String] = []
    var trueBlendMaterials: [String] = []
    
    for (meshInstance, _, effectiveRenderMode, _, _, _) in opaqueMeshes {
      // Get material name from the mesh instance's stored material properties
      let materialName = meshInstance.materialName ?? "<unnamed>"
      switch effectiveRenderMode {
      case .opaque: 
        opaqueCount += 1
        opaqueMaterials.append(materialName)
      case .cutoutCoverage: 
        cutoutCoverageCount += 1
        cutoutMaterials.append(materialName)
      case .overlayBlend: 
        overlayBlendCount += 1
        overlayMaterials.append(materialName)
      case .translucent: 
        trueBlendCount += 1
        trueBlendMaterials.append(materialName)
      }
    }
    for (meshInstance, _, _, effectiveRenderMode, _, _, _) in transparentMeshes {
      // Get material name from the mesh instance's stored material properties
      let materialName = meshInstance.materialName ?? "<unnamed>"
      switch effectiveRenderMode {
      case .opaque: 
        opaqueCount += 1
        opaqueMaterials.append(materialName)
      case .cutoutCoverage: 
        cutoutCoverageCount += 1
        cutoutMaterials.append(materialName)
      case .overlayBlend: 
        overlayBlendCount += 1
        overlayMaterials.append(materialName)
      case .translucent: 
        trueBlendCount += 1
        trueBlendMaterials.append(materialName)
      }
    }
    
    logger.trace("📊 Draw counts: Opaque=\(opaqueCount), CutoutCoverage=\(cutoutCoverageCount), OverlayBlend=\(overlayBlendCount), TrueBlend=\(trueBlendCount)")
    if !opaqueMaterials.isEmpty {
      logger.trace("  Opaque materials: \(opaqueMaterials.joined(separator: ", "))")
    }
    if !cutoutMaterials.isEmpty {
      logger.trace("  CutoutCoverage materials: \(cutoutMaterials.joined(separator: ", "))")
    }
    if !overlayMaterials.isEmpty {
      logger.trace("  OverlayBlend materials: \(overlayMaterials.joined(separator: ", "))")
    }
    if !trueBlendMaterials.isEmpty {
      logger.trace("  TrueBlend materials: \(trueBlendMaterials.joined(separator: ", "))")
    }
    
    // Render opaque meshes first (OPAQUE and CutoutCoverage)
    // Sort by render mode only (purely alpha-driven, no name-based logic)
    // Order: (1) opaque (face, body, eyes), (2) cutoutCoverage (hair)
    // Eyes render with depth write OFF, so they can be in the same pass as other opaque
    let sortedOpaqueMeshes = opaqueMeshes.sorted(by: { (mesh1: (instance: MeshInstance, matrix: mat4, effectiveRenderMode: MeshInstance.RenderMode, useAlphaHash: Bool, useAlphaToCoverage: Bool, usePolygonOffset: Bool), mesh2: (instance: MeshInstance, matrix: mat4, effectiveRenderMode: MeshInstance.RenderMode, useAlphaHash: Bool, useAlphaToCoverage: Bool, usePolygonOffset: Bool)) -> Bool in
      // Compute render priority: opaque=0, cutoutCoverage=1
      func renderModePriority(_ mode: MeshInstance.RenderMode) -> Int {
        switch mode {
        case .opaque: return 0
        case .cutoutCoverage: return 1
        case .overlayBlend, .translucent: return 2  // Shouldn't be in opaque pass, but handle gracefully
        }
      }
      return renderModePriority(mesh1.effectiveRenderMode) < renderModePriority(mesh2.effectiveRenderMode)
    })
    for (meshInstance, combinedModelMatrix, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset) in sortedOpaqueMeshes {
      guard effectiveRenderMode == .opaque else { continue }
      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: cameraPosition,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity,
        fillLightDirection: fillLight.direction,
        fillLightColor: fillLight.color,
        fillLightIntensity: fillLight.intensity,
        diffuseOnly: useDiffuseOnly,
        showTextureDebug: showTextureDebug,
        effectiveRenderMode: effectiveRenderMode,
        showFinalAlpha: showFinalAlpha,
        showClassification: showClassification,
        cutoutThreshold: cutoutThreshold,
        showUVDebug: showUVDebug,
        showUVRaw: showUVRaw,
        renderPassName: "ModelViewerOpaque",
        useAlphaHash: useAlphaHash,
        useAlphaToCoverage: useAlphaToCoverage,
        usePolygonOffset: usePolygonOffset,
        debugForceTransparentColor: false  // Opaque pass never forces transparent color
      )
    }
    
    // Second pass: CutoutCoverage (hair) with depth write ON
    glDepthMask(true)  // Depth write ON for hair
    for (meshInstance, combinedModelMatrix, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset) in sortedOpaqueMeshes {
      // Only render cutoutCoverage meshes in second pass (hair)
      guard effectiveRenderMode == .cutoutCoverage else { continue }
      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: cameraPosition,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity,
        fillLightDirection: fillLight.direction,
        fillLightColor: fillLight.color,
        fillLightIntensity: fillLight.intensity,
        diffuseOnly: useDiffuseOnly,
        showTextureDebug: showTextureDebug,
        effectiveRenderMode: effectiveRenderMode,
        showFinalAlpha: showFinalAlpha,
        showClassification: showClassification,
        cutoutThreshold: cutoutThreshold,
        showUVDebug: showUVDebug,
        showUVRaw: showUVRaw,
        renderPassName: "ModelViewerCutoutCoverage",
        useAlphaHash: useAlphaHash,
        useAlphaToCoverage: useAlphaToCoverage,
        usePolygonOffset: usePolygonOffset,
        debugForceTransparentColor: false
      )
    }

    // Render transparent meshes last (OverlayBlend and Translucent)
    // OverlayBlend (brows/lashes) are decal-style overlays - depth test ON, no depth write, no sorting needed
    // Translucent materials are sorted back-to-front (farthest first) for proper blending
    let overlayBlendMeshes = transparentMeshes.filter { $0.effectiveRenderMode == .overlayBlend }
    let translucentMeshes = transparentMeshes.filter { $0.effectiveRenderMode == .translucent }
    let sortedTranslucentMeshes = translucentMeshes.sorted(by: { $0.distance > $1.distance })
    
    // Render OverlayBlend decals first (depth test ON, no sorting)
    logger.trace("🔵 OverlayBlend decals: drawing \(overlayBlendMeshes.count) meshes")
    for (meshInstance, combinedModelMatrix, _, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset) in overlayBlendMeshes {
      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: cameraPosition,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity,
        fillLightDirection: fillLight.direction,
        fillLightColor: fillLight.color,
        fillLightIntensity: fillLight.intensity,
        diffuseOnly: useDiffuseOnly,
        showTextureDebug: showTextureDebug,
        effectiveRenderMode: effectiveRenderMode,
        showFinalAlpha: showFinalAlpha,
        showClassification: showClassification,
        cutoutThreshold: cutoutThreshold,
        showUVDebug: showUVDebug,
        showUVRaw: showUVRaw,
        renderPassName: "ModelViewerOverlayBlend",
        useAlphaHash: useAlphaHash,
        useAlphaToCoverage: useAlphaToCoverage,
        usePolygonOffset: usePolygonOffset,
        debugForceTransparentColor: false  // OverlayBlend outputs real alpha, no debug override
      )
    }
    
    // Render Translucent materials last (sorted back-to-front)
    logger.trace("🔵 Translucent pass: drawing \(sortedTranslucentMeshes.count) meshes")
    for (meshInstance, combinedModelMatrix, _, effectiveRenderMode, useAlphaHash, useAlphaToCoverage, usePolygonOffset) in sortedTranslucentMeshes {
      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: cameraPosition,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity,
        fillLightDirection: fillLight.direction,
        fillLightColor: fillLight.color,
        fillLightIntensity: fillLight.intensity,
        diffuseOnly: useDiffuseOnly,
        showTextureDebug: showTextureDebug,
        effectiveRenderMode: effectiveRenderMode,
        showFinalAlpha: showFinalAlpha,
        showClassification: showClassification,
        cutoutThreshold: cutoutThreshold,
        showUVDebug: showUVDebug,
        showUVRaw: showUVRaw,
        renderPassName: "ModelViewerTranslucent",
        useAlphaHash: useAlphaHash,
        useAlphaToCoverage: useAlphaToCoverage,
        usePolygonOffset: usePolygonOffset,
        debugForceTransparentColor: false
      )
    }
  }
  
  /// Compute effective renderMode based on transparencyDebugMode override
  private func computeEffectiveRenderMode(actualRenderMode: MeshInstance.RenderMode) -> MeshInstance.RenderMode {
    switch transparencyDebugMode {
    case "ForceOpaque":
      return .opaque
    case "ForceOverlayBlend":
      return .overlayBlend
    case "ForceCutoutCoverage":
      return .cutoutCoverage
    case "ForceTrueBlend":
      return .translucent
    default: // "Normal"
      return actualRenderMode
    }
  }
  
  /// Compute effective flags based on transparencyDebugMode and effectiveRenderMode
  /// All decisions are made here in ModelViewer before calling draw()
  /// OverlayBlend materials should NEVER use alpha-hash, alpha-to-coverage, or polygon offset
  private func computeEffectiveFlags(
    transparencyDebugMode: String,
    effectiveRenderMode: MeshInstance.RenderMode,
    actualUseAlphaHash: Bool
  ) -> (useAlphaHash: Bool, useAlphaToCoverage: Bool, usePolygonOffset: Bool) {
    switch transparencyDebugMode {
    case "ForceOpaque":
      return (false, false, false)
    case "ForceOverlayBlend":
      // ForceOverlayBlend: no dither, no discard, no polygon offset - just smooth blending
      return (false, false, false)
    case "ForceCutoutCoverage":
      // ForceCutoutCoverage: always use alpha-to-coverage (preferred for hair cards)
      return (true, true, true)  // useAlphaHash=true, useAlphaToCoverage=true, usePolygonOffset=true
    case "ForceTrueBlend":
      return (false, false, false)
    default: // "Normal"
      switch effectiveRenderMode {
      case .cutoutCoverage:
        // Normal mode with CutoutCoverage: use alpha-to-coverage by default
        return (actualUseAlphaHash, true, true)  // Default to alpha-to-coverage and polygon offset
      case .overlayBlend:
        // OverlayBlend: never use alpha-hash, alpha-to-coverage, or polygon offset
        return (false, false, false)
      default:
        return (false, false, false)
      }
    }
  }

  private func drawModelName() {
    let currentModelPath = modelPaths[safe: currentModelIndex] ?? modelPaths[0]
    let modelName = (currentModelPath.components(separatedBy: "/").last ?? "Unknown").replacingOccurrences(
      of: "_", with: " "
    ).titleCased

    let centerX = Float(Engine.viewportSize.width) / 2

    // In OpenGL, Y=0 is at bottom, so we calculate from bottom
    // Position model name and animation name near bottom of screen
    let modelNameY = modelNameBaseline
    let animationNameY = animationNameBaseline

    // Gradient divider line between model name and animation name
    // Fade from both ends: clear -> white -> clear
    let dividerGradient = Gradient(
      colors: [.clear, .white.withAlphaComponent(0.15), .white.withAlphaComponent(0.15), .clear],
      locations: [0.0, 0.1, 0.9, 1.0]
    )
    let dividerWidth = modelNameDividerWidth
    let dividerHeight = modelNameDividerHeight

    // Divider positioned between model name and animation name
    let dividerY = (modelNameY + animationNameY) / 2
    let divider = Rect(
      x: centerX - dividerWidth / 2, y: dividerY - dividerHeight / 2, width: dividerWidth, height: dividerHeight)
    divider.fill(with: dividerGradient)

    // Draw model name with Q/E prompts
    // Align prompts vertically with text baseline
    prevModelPrompt.iconOpacity = 0.6
    prevModelPrompt.draw(
      at: Point(
        centerX - promptAreaWidth * promptHorizontalFactor,
        modelNameY - modelPromptVerticalOffset
      ),
      anchor: .topRight
    )

    modelName.draw(
      at: Point(centerX, modelNameY),
      style: .itemName,
      anchor: .bottom
    )

    nextModelPrompt.iconOpacity = 0.6
    nextModelPrompt.draw(
      at: Point(
        centerX + promptAreaWidth * promptHorizontalFactor,
        modelNameY - modelPromptVerticalOffset
      ),
      anchor: .topLeft
    )

    // Draw animation name and 1/3 prompts
    // Always draw the prompts, even if no animations are loaded
    prevAnimationPrompt.iconOpacity = 0.6
    prevAnimationPrompt.draw(
      at: Point(
        centerX - promptAreaWidth * promptHorizontalFactor,
        animationNameY + animationPromptVerticalOffset
      ),
      anchor: .bottomRight
    )

    // Only draw animation name if animations are available
    if !currentAnimationNames.isEmpty {
      let currentAnimationName = currentAnimationNames[safe: currentAnimationIndex] ?? currentAnimationNames[0]
      let displayText = currentAnimationName  // Removed < and >

      displayText.draw(
        at: Point(centerX, animationNameY),
        style: .itemDescription,
        anchor: .top
      )
    }

    nextAnimationPrompt.iconOpacity = 0.6
    nextAnimationPrompt.draw(
      at: Point(
        centerX + promptAreaWidth * promptHorizontalFactor,
        animationNameY + animationPromptVerticalOffset
      ),
      anchor: .bottomLeft
    )
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

// Custom camera for ModelViewer with extended zoom range
class ModelViewerCamera: ItemInspectionCamera {
  private let modelViewerMaxDistance: Float = 10000.0
  private let modelViewerMinDistance: Float = 0.01
  
  /// Initialize with defaults optimized for character viewing
  override init(
    target: vec3 = vec3(0.0, 0.85, 0.0),  // Target at character's torso/center height
    distance: Float = 2.0,  // Good viewing distance for characters
    modelYaw: Float = 45.0,  // Start with model facing diagonally
    modelPitch: Float = 0.0  // Start with model level
  ) {
    super.init(target: target, distance: distance, modelYaw: modelYaw, modelPitch: modelPitch)
  }

  override func processMouseScroll(_ yOffset: Float) {
    let scrollSensitivity: Float = 0.1
    let scrollDelta = yOffset * scrollSensitivity
    zoomVelocity += scrollDelta
  }
  
  /// Override keyboard processing to skip Q and E (used for model navigation in ModelViewer)
  @MainActor override func processKeyboardState(_ keyboard: Keyboard, _ deltaTime: Float) {
    // Don't process keyboard input during reset animation
    guard !isResetting else { return }

    // Speed modifiers
    var speed: Float = 1
    if keyboard.state(of: .leftShift) == .pressed || keyboard.state(of: .rightShift) == .pressed { speed = 3 }
    if keyboard.state(of: .leftAlt) == .pressed || keyboard.state(of: .rightAlt) == .pressed { speed = 1 / 3 }

    // WASD and Arrow keys for model rotation
    let rotationSpeed = keyboardSensitivity * deltaTime * speed

    if keyboard.state(of: .w) == .pressed || keyboard.state(of: .up) == .pressed {
      modelPitch += rotationSpeed
      if modelPitch > 89.0 { modelPitch = 89.0 }
      updateCameraPosition()  // Update camera when pitch changes
    }
    if keyboard.state(of: .s) == .pressed || keyboard.state(of: .down) == .pressed {
      modelPitch -= rotationSpeed
      if modelPitch < -89.0 { modelPitch = -89.0 }
      updateCameraPosition()  // Update camera when pitch changes
    }
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      modelYaw -= rotationSpeed
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      modelYaw += rotationSpeed
    }

    // NOTE: Q and E are intentionally skipped here - they're used for model navigation in ModelViewer
    // Use scroll wheel or +/- keys for zoom instead

    // R for reset
    if keyboard.state(of: .r) == .pressed {
      resetToInitialPosition()
    }
  }

  override func update(deltaTime: Float) {
    // Handle reset animation (copy from parent but with our distance limits)
    if isResetting {
      resetStartTime += deltaTime
      let progress = min(resetStartTime / resetDuration, 1.0)
      let easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress)

      modelYaw = resetStartYaw + (resetTargetYaw - resetStartYaw) * easedProgress
      modelPitch = resetStartPitch + (resetTargetPitch - resetStartPitch) * easedProgress
      distance = resetStartDistance + (resetTargetDistance - resetStartDistance) * easedProgress

      let targetPanOffset = vec3(0, 0, 0)
      panOffset = resetStartPanOffset + (targetPanOffset - resetStartPanOffset) * easedProgress
      target = initialTarget + panOffset
      updateCameraPosition()

      if progress >= 1.0 {
        isResetting = false
        modelYaw = resetTargetYaw
        modelPitch = resetTargetPitch
        distance = resetTargetDistance
        panOffset = vec3(0, 0, 0)
        target = initialTarget
        updateCameraPosition()
      }
      return
    }

    // Apply momentum if not dragging
    if !isDragging {
      modelYaw += angularVelocity.yaw * deltaTime
      modelPitch += angularVelocity.pitch * deltaTime
      updateCameraPosition()
      angularVelocity.yaw *= friction
      angularVelocity.pitch *= friction
    }

    // Apply zoom momentum with CUSTOM distance limits
    if abs(zoomVelocity) > 0.01 {
      distance -= zoomVelocity * deltaTime

      // Clamp distance to custom bounds (NOT parent's bounds)
      if distance < modelViewerMinDistance {
        distance = modelViewerMinDistance
        zoomVelocity = 0.0
      }
      if distance > modelViewerMaxDistance {
        distance = modelViewerMaxDistance
        zoomVelocity = 0.0
      }

      updateCameraPosition()
      zoomVelocity *= zoomFriction
    }

    // Apply pan momentum
    if length(panVelocity) > 0.01 {
      let panDelta = panVelocity * deltaTime
      target += panDelta
      panOffset += panDelta
      updateCameraPosition()
      panVelocity *= panFriction
    }
  }
}
