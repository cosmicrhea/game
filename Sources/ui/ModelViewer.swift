import Assimp

final class ModelViewer: RenderLoop {
  // UI
  private let promptList = PromptList(.modelViewer)
  private let secondaryPromptList = PromptList(.modelViewerControls, axis: .vertical)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

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

      if let assimpScene = loaded.first?.scene {
        // Wrap in our Scene wrapper
        let scene = Scene(assimpScene)
        currentScene = scene
        currentAnimationNames = scene.animations.enumerated().map { idx, a in
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
    guard let scene = currentScene,
      currentAnimationIndex < scene.animations.count
    else {
      logger.warning(
        "ModelViewer: Cannot play animation - scene: \(currentScene != nil), index: \(currentAnimationIndex), count: \(currentScene?.animations.count ?? 0)"
      )
      return
    }

    let animation = scene.animations[currentAnimationIndex]
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
        let origin = Point(Float(Engine.viewportSize.width) - 400, Float(Engine.viewportSize.height) / 2)
        secondaryPromptList.draw(
          prompts: prompts,
          inputSource: .player1,
          origin: origin,
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
      ? nodeAnimator.calculateBoneTransforms(scene: currentScene!) : nodeAnimator.getAllNodeTransforms()

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
    guard let scene = currentScene else { return mat4(1) }

    // Find the mesh index in the scene
    guard let meshIndex = findMeshIndex(for: meshInstance, in: scene) else {
      return mat4(1)
    }

    // Get the mesh from the scene
    let mesh = scene.meshes[meshIndex]

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

  private func findMeshIndex(for meshInstance: MeshInstance, in scene: Scene) -> Int? {
    let index = scene.meshes.firstIndex { $0 === meshInstance.mesh }
    logger.trace("ModelViewer: Looking for mesh, found index: \(index ?? -1)")
    return index
  }

  private func findNodeName(for meshIndex: Int, in scene: Scene) -> String? {
    return findNodeNameRecursive(node: scene.rootNode, meshIndex: meshIndex)
  }

  private func findNodeNameRecursive(node: Node, meshIndex: Int) -> String? {
    // Check if this node contains the mesh
    if node.meshes.contains(meshIndex) {
      logger.trace("ModelViewer: Found node '\(node.name ?? "unnamed")' for mesh index \(meshIndex)")
      return node.name
    }

    // Search in child nodes
    for child in node.children {
      if let found = findNodeNameRecursive(node: child, meshIndex: meshIndex) {
        return found
      }
    }

    return nil
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

    modelName.draw(
      at: Point(centerX, 128 + 32),
      style: .itemName,
      anchor: .bottom
    )

    // Draw current animation name below model name
    if !currentAnimationNames.isEmpty {
      let currentAnimationName = currentAnimationNames[safe: currentAnimationIndex] ?? currentAnimationNames[0]
      //      let playStatus = nodeAnimator.playing ? "▶" : "⏸"
      //      let displayText = "\(playStatus) \(currentAnimationName)"
      let displayText = "\(currentAnimationName)"

      displayText.draw(
        at: Point(centerX, 128),
        style: .itemDescription,
        anchor: .bottom
      )
    }
  }
}

// Custom camera for ModelViewer with extended zoom range
class ModelViewerCamera: ItemInspectionCamera {
  private let modelViewerMaxDistance: Float = 10.0
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
