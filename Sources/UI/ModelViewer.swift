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
    "Actors/alex",
    "Actors/goth_girl",
    //"Actors/guard",
    "Actors/marit",
    "Actors/rat",
  ]
  private var currentModelIndex: Int = 0
  private var meshInstances: [MeshInstance] = []
  private let loadingProgress = LoadingProgress()

  // Scene/Animations
  private var currentAnimationNames: [String] = []
  private var currentAnimationIndex: Int = 0
  private var nodeAnimator = NodeAnimator()
  private var currentScene: Scene?

  // Camera / lights
  private var camera = ModelViewerCamera()
  private var light = Light.itemInspection
  private var fillLight = Light.itemInspectionFill

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // UI visibility toggle
  private var showControls: Bool = true

  init() {
    Task { await loadCurrentModel() }
  }

  // MARK: - Loading
  private func loadCurrentModel() async {
    loadingProgress.reset()
    meshInstances.removeAll()
    currentAnimationNames.removeAll()

    let path = modelPaths[safe: currentModelIndex] ?? modelPaths[0]
    do {
      let loaded = try await MeshInstance.loadAsync(
        path: path,
        onSceneProgress: { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.loadingProgress.updateSceneProgress(progress)
          }
        },
        onTextureProgress: { [weak self] current, total, progress in
          Task { @MainActor [weak self] in
            self?.loadingProgress.updateTextureProgress(current: current, total: total, progress: progress)
          }
        }
      )
      self.meshInstances = loaded
      self.loadingProgress.markCompleted()

      if let sceneData = loaded.first?.sceneData {
        currentScene = sceneData
        currentAnimationNames = sceneData.animations.enumerated().map { idx, a in
          if let name = a.name, !name.isEmpty { return name }
          return "Animation \(idx + 1)"
        }

        currentAnimationIndex = 0
        playCurrentAnimation()
      }
    } catch {
      self.meshInstances = []
      self.currentAnimationNames = []
      self.loadingProgress.progressMessages.append("Failed to load: \(path)")
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
      currentAnimationIndex < sceneData.animations.count
    else {
      logger.warning(
        "ModelViewer: Cannot play animation - scene: \(currentScene != nil), index: \(currentAnimationIndex), count: \(currentScene?.animations.count ?? 0)"
      )
      return
    }

    let animation = sceneData.animations[currentAnimationIndex]
    logger.trace(
      "ModelViewer: Playing animation \(currentAnimationIndex): \(currentAnimationNames[safe: currentAnimationIndex] ?? "Unknown")"
    )
    nodeAnimator.play(animation: animation)
  }

  private func toggleAnimation() {
    if nodeAnimator.playing {
      nodeAnimator.pause()
    } else {
      nodeAnimator.resume()
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

    nodeAnimator.update(deltaTime: deltaTime)

    // Debug: Print animation status every 2 seconds
    if Int(nodeAnimator.animationTime) % 2 == 0 && nodeAnimator.playing {
      logger.trace(
        "ModelViewer: Animation playing - time: \(nodeAnimator.animationTime), transforms: \(nodeAnimator.getAllNodeTransforms().count)"
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
    } else if loadingProgress.isLoading {
      drawLoadingProgress()
    }

    if showControls {
      drawModelName()

      // Prompt lists
      promptList.group = .modelViewer
      promptList.draw()

      if let prompts = PromptGroup.prompts[.modelViewerControls] {
        let viewportHeight = Float(Engine.viewportSize.height)
        let originX = Float(Engine.viewportSize.width) - 400

        // Calculate prompt list size and header height
        let promptListSize = secondaryPromptList.size(for: prompts, inputSource: .player1)
        let headerStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 24, color: .white)
        let headerHeight = "Controls".size(with: headerStyle).height
        let headerSpacing: Float = 16
        let dividerHeight: Float = 2

        // Position from top of screen (higher Y = higher on screen in OpenGL)
        // In OpenGL, Y=0 is at bottom, viewportHeight is at top
        // Position near top with some margin
        let topMargin: Float = 100
        let headerTopY = viewportHeight - topMargin

        // Draw "Controls" header first (at the top)
        "Controls".draw(
          at: Point(originX, headerTopY),
          style: headerStyle,
          anchor: .bottomLeft
        )

        // Draw divider below the header
        let headerBottomY = headerTopY - headerHeight
        let dividerGradient = Gradient(colors: [.clear, .white.withAlphaComponent(0.15)], locations: [0.0, 0.1])
        let dividerWidth: Float = 512
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
  }

  private func draw3DModel() {
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
    let view = camera.getViewMatrix()
    let cameraModelMatrix = camera.getModelMatrix()

    // Get all bone transforms for skeletal animation
    let boneTransforms =
      currentScene != nil
      ? nodeAnimator.calculateBoneTransforms(sceneData: currentScene!) : nodeAnimator.getAllNodeTransforms()

    meshInstances.forEach { meshInstance in
      // Update bone transforms for skeletal meshes
      meshInstance.updateBoneTransforms(boneTransforms)

      // Get animated transform for this mesh's node (if it exists)
      let animatedTransform = getAnimatedTransform(for: meshInstance)

      // Combine camera model matrix with mesh transform and animation
      let combinedModelMatrix = cameraModelMatrix * meshInstance.transformMatrix * animatedTransform

      meshInstance.draw(
        projection: projection,
        view: view,
        modelMatrix: combinedModelMatrix,
        cameraPosition: camera.position,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity,
        fillLightDirection: fillLight.direction,
        fillLightColor: fillLight.color,
        fillLightIntensity: fillLight.intensity,
        diffuseOnly: false
      )
    }
  }

  private func getAnimatedTransform(for meshInstance: MeshInstance) -> mat4 {
    guard let sceneData = currentScene else { return mat4(1) }

    // Find the mesh index in the scene
    guard let meshIndex = findMeshIndex(for: meshInstance, in: sceneData) else {
      return mat4(1)
    }

    // Get the mesh from the scene
    let mesh = sceneData.meshes[meshIndex]

    // If this mesh has bones, we need to apply skeletal animation
    if mesh.numberOfBones > 0 {
      // This is a skeletal mesh - let's try applying different bone transforms
      // to see if we can get some bone movement

      // Try applying the Hips bone transform (should show some movement)
      let hipsBoneName = "Hips"
      let hipsTransform = nodeAnimator.getNodeTransform(nodeName: hipsBoneName)

      if hipsTransform != mat4(1) {
        return hipsTransform
      } else {
        // Fall back to root bone if hips doesn't have animation
        let rootBoneName = "Root"
        return nodeAnimator.getNodeTransform(nodeName: rootBoneName)
      }
    } else {
      // This is a static mesh (like the handgun) - no animation
      return mat4(1)
    }
  }

  private func findMeshIndex(for meshInstance: MeshInstance, in sceneData: Scene) -> Int? {
    // Since Mesh is a struct, we need to compare by value or use a different approach
    // For now, we'll search by comparing mesh properties
    let index = sceneData.meshes.firstIndex { mesh in
      mesh.numberOfVertices == meshInstance.mesh.numberOfVertices
        && mesh.numberOfFaces == meshInstance.mesh.numberOfFaces
        && mesh.materialIndex == meshInstance.mesh.materialIndex
    }
    logger.trace("ModelViewer: Looking for mesh, found index: \(index ?? -1)")
    return index
  }

  private func drawLoadingProgress() {
    let progressStyle = TextStyle(
      fontName: "CreatoDisplay-Medium",
      fontSize: 16,
      color: .white,
      strokeWidth: 1,
      strokeColor: .gray900
    )
    let startY = Float(Engine.viewportSize.height) - 40
    let lineHeight: Float = 24
    for (index, message) in loadingProgress.progressMessages.enumerated() {
      let y = startY - Float(index) * lineHeight
      message.draw(at: Point(40, y), style: progressStyle, anchor: .topLeft)
    }
  }

  private func drawModelName() {
    let currentModelPath = modelPaths[safe: currentModelIndex] ?? modelPaths[0]
    let modelName = (currentModelPath.components(separatedBy: "/").last ?? "Unknown").replacingOccurrences(
      of: "_", with: " "
    ).titleCased

    let centerX = Float(Engine.viewportSize.width) / 2
    let viewportHeight = Float(Engine.viewportSize.height)

    // In OpenGL, Y=0 is at bottom, so we calculate from bottom
    // Position model name and animation name near bottom of screen
    let modelNameY: Float = 160  // 160 pixels from bottom
    let animationNameY: Float = 128  // 128 pixels from bottom

    // Gradient divider line between model name and animation name
    // Fade from both ends: clear -> white -> clear
    let dividerGradient = Gradient(
      colors: [.clear, .white.withAlphaComponent(0.15), .white.withAlphaComponent(0.15), .clear],
      locations: [0.0, 0.1, 0.9, 1.0]
    )
    let dividerWidth: Float = 512
    let dividerHeight: Float = 2

    // Divider positioned between model name and animation name
    let dividerY = (modelNameY + animationNameY) / 2
    let divider = Rect(
      x: centerX - dividerWidth / 2, y: dividerY - dividerHeight / 2, width: dividerWidth, height: dividerHeight)
    divider.fill(with: dividerGradient)

    // Draw model name with Q/E prompts
    // Hardcode prompt positions to 400px wide from center
    let promptAreaWidth: Float = 400

    // Align prompts vertically with text baseline
    prevModelPrompt.iconOpacity = 0.6
    prevModelPrompt.draw(
      at: Point(centerX - promptAreaWidth * 0.4, modelNameY),
      anchor: .right
    )

    modelName.draw(
      at: Point(centerX, modelNameY),
      style: .itemName,
      anchor: .center
    )

    nextModelPrompt.iconOpacity = 0.6
    nextModelPrompt.draw(
      at: Point(centerX + promptAreaWidth * 0.4, modelNameY),
      anchor: .left
    )

    // Draw animation name and 1/3 prompts
    // Always draw the prompts, even if no animations are loaded
    prevAnimationPrompt.iconOpacity = 0.6
    prevAnimationPrompt.draw(
      at: Point(centerX - promptAreaWidth * 0.4, animationNameY),
      anchor: .right
    )

    // Only draw animation name if animations are available
    if !currentAnimationNames.isEmpty {
      let currentAnimationName = currentAnimationNames[safe: currentAnimationIndex] ?? currentAnimationNames[0]
      let displayText = currentAnimationName  // Removed < and >

      displayText.draw(
        at: Point(centerX, animationNameY),
        style: .itemDescription,
        anchor: .center
      )
    }

    nextAnimationPrompt.iconOpacity = 0.6
    nextAnimationPrompt.draw(
      at: Point(centerX + promptAreaWidth * 0.4, animationNameY),
      anchor: .left
    )
  }
}

// Custom camera for ModelViewer with extended zoom range
class ModelViewerCamera: ItemInspectionCamera {
  private let modelViewerMaxDistance: Float = 10000.0
  private let modelViewerMinDistance: Float = 0.01

  override func processMouseScroll(_ yOffset: Float) {
    let scrollSensitivity: Float = 0.1
    let scrollDelta = yOffset * scrollSensitivity
    zoomVelocity += scrollDelta
  }

  override func update(deltaTime: Float) {
    // Apply zoom momentum with custom distance limits
    if abs(zoomVelocity) > 0.01 {
      distance += zoomVelocity * deltaTime

      // Clamp distance to custom bounds
      if distance < modelViewerMinDistance {
        distance = modelViewerMinDistance
        zoomVelocity = 0.0
      }
      if distance > modelViewerMaxDistance {
        distance = modelViewerMaxDistance
        zoomVelocity = 0.0
      }
    }

    // Apply friction to slow down momentum
    zoomVelocity *= zoomFriction

    // Call parent update for other camera logic
    super.update(deltaTime: deltaTime)
  }
}
