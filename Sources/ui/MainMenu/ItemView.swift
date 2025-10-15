import Assimp
import GL
import GLFW
import GLMath

import class Foundation.Bundle

final class ItemView: RenderLoop {
  private let item: Item
  private let promptList = PromptList(.itemView)
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // 3D model rendering
  private let meshInstances: [MeshInstance]
  private let program = try! GLProgram("Common/basic 2")
  private var camera = OrbitCamera()

  // Item info styling is now defined inline in drawItemInfo() to match InventoryView

  // Mouse tracking for camera control
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  /// Completion callback for when item inspection is finished.
  var onItemFinished: (() -> Void)?

  init(item: Item) {
    self.item = item

    // Load 3D model if available
    if let modelPath = item.modelPath {
      let scenePath = Bundle.module.path(forResource: modelPath, ofType: "glb")!
      let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])

      meshInstances = scene.meshes
        .filter { $0.numberOfVertices > 0 }
        .map { mesh in
          let transformMatrix = scene.getTransformMatrix(for: mesh)
          return MeshInstance(scene: scene, mesh: mesh, transformMatrix: transformMatrix)
        }
    } else {
      meshInstances = []
    }

    // Set up camera for item inspection
    camera.target = vec3(0, 0, 0)  // Orbit around the center
    camera.distance = 3.0  // Start a bit back from the item
    camera.yaw = 0  // Start facing forward
    camera.pitch = 0  // Level view
  }

  func update(window: GLFWWindow, deltaTime: Float) {
    camera.update(deltaTime: deltaTime)
    print(window.mouse.state(of: .left))
    print(window.mouse.state(of: .button1))
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .escape:
      onItemFinished?()
    default:
      break
    }
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onMouseButton(window: GLFWWindow, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    print("onMouseButton: \(button), state: \(state)")
    if button == .left {
      if state == .pressed {
        camera.startDragging()
      } else if state == .released {
        camera.stopDragging()
      }
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
    }

    // Draw item information
    drawItemInfo()

    // Draw prompt list
    promptList.draw()
  }

  private func draw3DModel() {
    program.use()
    // Use fixed FOV - zoom is handled by distance in OrbitCamera
    program.setMat4("projection", value: GLMath.perspective(45.0, 1, 0.001, 1000.0))
    program.setMat4("view", value: camera.getViewMatrix())

    // Draw all mesh instances with proper model matrix
    meshInstances.forEach { meshInstance in
      // Set model matrix for this mesh using the transform from Assimp
      program.setMat4("model", value: meshInstance.transformMatrix)
      meshInstance.draw()
    }
  }

  private func drawItemInfo() {
    let screenWidth = Float(Engine.viewportSize.width)
    let screenHeight = Float(Engine.viewportSize.height)

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
}
