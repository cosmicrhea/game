import Assimp

final class ItemView: RenderLoop {
  private let item: Item
  private let promptList = PromptList(.itemView)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")
  private let itemDescriptionView = ItemDescriptionView()

  // 3D model rendering
  private var meshInstances: [MeshInstance] = []
  private var camera = ItemInspectionCamera()
  private var light = Light.itemInspection
  private var fillLight = Light.itemInspectionFill

  // Loading state
  private let loadingProgress = LoadingProgress()

  // Mouse tracking for camera control
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Debug state
  private var showDebugInfo: Bool = false
  private var useDiffuseOnly: Bool = false

  /// Completion callback for when item inspection is finished.
  var onItemFinished: (() -> Void)?

  init(item: Item) {
    self.item = item
    self.itemDescriptionView.item = item

    // Start async loading if model is available
    if let modelPath = item.modelPath {
      Task { await loadModelAsync(path: modelPath) }
    }
  }

  /// Load 3D model asynchronously with progress updates
  private func loadModelAsync(path: String) async {
    do {
      meshInstances = try await MeshInstance.loadAsync(
        path: path,
        onSceneProgress: { progress in
          Task { @MainActor in
            //            print("Scene progress: \(progress)")
            self.loadingProgress.updateSceneProgress(progress)
          }
        },
        onTextureProgress: { current, total, progress in
          Task { @MainActor in
            //            print("Texture progress: \(current)/\(total) - \(progress)")
            self.loadingProgress.updateTextureProgress(current: current, total: total, progress: progress)
          }
        }
      )

      await MainActor.run {
        self.loadingProgress.markCompleted()
      }
    } catch {
      print("Failed to load model: \(error)")
      await MainActor.run {
        self.loadingProgress.markCompleted()
      }
    }
  }

  // func update(deltaTime: Float) {
  //   camera.update(deltaTime: deltaTime)
  // }

  func update(window: Window, deltaTime: Float) {
    camera.update(deltaTime: deltaTime)
    camera.processKeyboardState(window.keyboard, deltaTime)
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .escape:
      UISound.cancel()
      onItemFinished?()
    case .backspace:
      UISound.select()
      showDebugInfo.toggle()
    case .y:
      UISound.select()
      adjustMainLightIntensity(0.1)
    case .u:
      UISound.select()
      adjustMainLightIntensity(-0.1)
    case .i:
      UISound.select()
      adjustFillLightIntensity(0.1)
    case .h:
      UISound.select()
      adjustFillLightIntensity(-0.1)
    case .j:
      UISound.select()
      adjustAmbientLight(0.02)
    case .k:
      UISound.select()
      adjustAmbientLight(-0.02)
    case .b:
      UISound.select()
      resetLights()
    case .period:
      UISound.select()
      useDiffuseOnly.toggle()
    default:
      break
    }
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if button == .left {
      if state == .pressed {
        camera.startDragging()
      } else if state == .released {
        camera.stopDragging()
      }
    } else if button == .right && state == .pressed {
      // Right-click to close item view
      UISound.cancel()
      onItemFinished?()
    }
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    let isAltPressed =
      window.keyboard.state(of: .leftAlt) == .pressed || window.keyboard.state(of: .rightAlt) == .pressed
    camera.processMousePosition(Float(x), Float(y), isAltPressed: isAltPressed)
  }

  func draw() {
    // Draw ambient background
    ambientBackground.draw { shader in
      shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
      shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
      shader.setFloat("uMottle", value: 0.35)
      shader.setFloat("uGrain", value: 0.08)
      shader.setFloat("uVignette", value: 0.35)
      shader.setFloat("uDust", value: 0.06)
    }

    // Draw 3D model if available
    if !meshInstances.isEmpty {
      draw3DModel()
    } else if loadingProgress.isLoading {
      // Show loading progress
      drawLoadingProgress()
    }

    // Draw item information
    itemDescriptionView.draw()

    // Draw prompt list
    promptList.draw()

    // Draw debug info if enabled
    if showDebugInfo {
      camera.drawDebugInfo()
      drawLightControlsHelp()
    }
  }

  private func draw3DModel() {
    // Use actual window aspect ratio to prevent squishing
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
    let view = camera.getViewMatrix()
    let modelMatrix = camera.getModelMatrix()

    // Draw all mesh instances
    meshInstances.forEach { meshInstance in
      // Combine the camera's model matrix with the mesh's transform matrix
      let combinedModelMatrix = modelMatrix * meshInstance.transformMatrix

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
        diffuseOnly: useDiffuseOnly
      )
    }
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
      message.draw(
        at: Point(40, y),
        style: progressStyle,
        anchor: .topLeft
      )
    }
  }

  // MARK: - Light Controls

  private func adjustMainLightIntensity(_ delta: Float) {
    light.intensity = max(0.0, min(10.0, light.intensity + delta))
    print("Main light intensity: \(light.intensity)")
  }

  private func adjustFillLightIntensity(_ delta: Float) {
    fillLight.intensity = max(0.0, min(5.0, fillLight.intensity + delta))
    print("Fill light intensity: \(fillLight.intensity)")
  }

  private func adjustAmbientLight(_ delta: Float) {
    // We'll need to pass this to the shader - for now just print
    print("Ambient light adjustment: \(delta)")
  }

  private func resetLights() {
    light = Light.itemInspection
    fillLight = Light.itemInspectionFill
    print("Lights reset to defaults")
  }

  private func drawLightControlsHelp() {
    let helpStyle = TextStyle(
      fontName: "CreatoDisplay-Medium",
      fontSize: 14,
      color: .white,
      strokeWidth: 1,
      strokeColor: .gray900
    )

    let startX: Float = 40
    let startY: Float = 200
    let lineHeight: Float = 20

    let helpTexts = [
      "Light Controls:",
      "Y/U: Main light intensity",
      "I/H: Fill light intensity",
      "J/K: Ambient light",
      "B: Reset lights",
      ".: Toggle diffuse-only mode",
      "",
      "Current: Main=\(String(format: "%.1f", light.intensity)), Fill=\(String(format: "%.1f", fillLight.intensity))",
      "Mode: \(useDiffuseOnly ? "Diffuse Only" : "Full PBR")",
    ]

    for (index, text) in helpTexts.enumerated() {
      let y = startY + Float(index) * lineHeight
      text.draw(
        at: Point(startX, y),
        style: helpStyle,
        anchor: .topLeft
      )
    }
  }
}
