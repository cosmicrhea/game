import Assimp
import GL
import GLFW
import GLMath

import class Foundation.Bundle
import class Foundation.NSArray

final class ItemView: RenderLoop {
  private let item: Item
  private let promptList = PromptList(.itemView)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // 3D model rendering
  private var meshInstances: [MeshInstance] = []
  private var camera = OrbitCamera()
  private let light = Light.itemInspection()

  // Loading state
  private let loadingProgress = LoadingProgress()

  // Item info styling is now defined inline in drawItemInfo() to match InventoryView

  // Mouse tracking for camera control
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  // Debug state
  private var showDebugInfo: Bool = false

  /// Completion callback for when item inspection is finished.
  var onItemFinished: (() -> Void)?

  init(item: Item) {
    self.item = item

    // Set up camera for item inspection
    camera.target = vec3(0, 0, 0)  // Orbit around the center
    camera.distance = 2.0  // Start closer to the item
    // yaw and pitch will use the default values from OrbitCamera init (-35.6, 14.1)

    // Start async loading if model is available
    if let modelPath = item.modelPath {
      Task {
        await loadModelAsync(path: modelPath)
      }
    }
  }

  /// Load 3D model asynchronously with progress updates
  private func loadModelAsync(path: String) async {
    do {
      meshInstances = try await MeshInstance.loadAsync(
        path: path,
        onSceneProgress: { progress in
          Task { @MainActor in
            print("Scene progress: \(progress)")
            self.loadingProgress.updateSceneProgress(progress)
          }
        },
        onTextureProgress: { current, total, progress in
          Task { @MainActor in
            print("Texture progress: \(current)/\(total) - \(progress)")
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

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .escape:
      UISound.cancel()
      onItemFinished?()
    case .backspace:
      UISound.select()
      showDebugInfo.toggle()
    default:
      break
    }
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onMouseButton(window: GLFWWindow, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
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

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    camera.processMousePosition(Float(x), Float(y))
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
    drawItemInfo()

    // Draw prompt list
    promptList.draw()

    // Draw debug info if enabled
    if showDebugInfo {
      camera.drawDebugInfo()
    }
  }

  private func draw3DModel() {
    // Use actual window aspect ratio to prevent squishing
    let aspectRatio = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let projection = GLMath.perspective(45.0, aspectRatio, 0.001, 1000.0)
    let view = camera.getViewMatrix()

    // Draw all mesh instances
    meshInstances.forEach { meshInstance in
      meshInstance.draw(
        projection: projection,
        view: view,
        lightDirection: light.direction,
        lightColor: light.color,
        lightIntensity: light.intensity
      )
    }
  }

  private func drawItemInfo() {
    let screenWidth = Float(Engine.viewportSize.width)

    // Position text at the bottom of the screen, similar to InventoryView
    // but using consistent bottom positioning instead of grid-relative positioning
    let labelX: Float = 40  // Left-align with some margin
    let labelY: Float = 160  // 160 pixels from bottom of screen

    // Use the same styles as InventoryView
    let nameStyle = TextStyle(
      fontName: "CreatoDisplay-Bold",
      fontSize: 28,
      color: .white,
      strokeWidth: 2,
      strokeColor: .gray700
    )

    let descriptionStyle = TextStyle(
      fontName: "CreatoDisplay-Medium",
      fontSize: 20,
      color: .gray300,
      strokeWidth: 1,
      strokeColor: .gray900
    )

    // Draw item name
    item.name.draw(
      at: Point(labelX, labelY),
      style: nameStyle,
      wrapWidth: screenWidth * 0.8,
      anchor: .topLeft
    )

    // Draw item description below the name
    if let description = item.description {
      let descriptionY = labelY - 40
      description.draw(
        at: Point(labelX, descriptionY),
        style: descriptionStyle,
        wrapWidth: screenWidth * 0.8,
        anchor: .topLeft
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
}
