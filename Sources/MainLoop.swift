import Assimp
import GL
import GLFW
import GLMath

import class Foundation.Bundle

/// The main game loop that handles rendering and input.
@MainActor
final class MainLoop: RenderLoop {

  // Scene and camera
  /// The free camera for navigating the scene.
  private var camera = FreeCamera()

  // Triangle demo
  /// Test triangle renderer for basic geometry testing.
  private let testTriangle = TestTriangle()

  // Assimp mesh
  /// Array of mesh renderers for 3D objects.
  private let meshInstances: [MeshInstance]

  // UI resources
  /// Text style using the Determination font.
  private let determinationStyle = TextStyle(fontName: "Determination", fontSize: 32, color: .white)
  /// Callout UI component for displaying hints.
  private var callout = Callout("Find the triangle and key", icon: .chevron)
  /// Input prompts component for controller/keyboard icons.
  private let inputPrompts: InputPrompts

  // State
  private var objectiveVisible: Bool = true
  private var showDebugText: Bool = false

  /// The main shader program for rendering.
  private let program = try! GLProgram("Common/basic 2")

  init() {
    let scenePath = Bundle.module.path(forResource: "Scenes/cabin_interior", ofType: "glb")!
    let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
    print("\(scene.rootNode)")

    meshInstances = scene.meshes
      .filter { $0.numberOfVertices > 0 }
      .map { MeshInstance(scene: scene, mesh: $0) }

    inputPrompts = InputPrompts()
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    guard window.isFocused else { return }
    camera.processMousePosition(Float(x), Float(y))
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .o:
      UISound.select()
      toggleObjective()

    case .backspace:
      UISound.select()
      showDebugText.toggle()

    default:
      break
    }
  }

  func update(window: GLFWWindow, deltaTime: Float) {
    camera.processKeyboardState(window.keyboard, deltaTime)

    // Update callout animation
    callout.visible = objectiveVisible
    callout.update(deltaTime: deltaTime)
  }

  func toggleObjective() {
    objectiveVisible.toggle()
  }

  func draw() {
    program.use()
    program.setMat4("projection", value: GLMath.perspective(camera.zoom, 1, 0.001, 1000.0))
    program.setMat4("view", value: camera.getViewMatrix())
    program.setMat4("model", value: mat4(1))

    // Triangle
    testTriangle.draw()

    // Meshes
    meshInstances.forEach { $0.draw() }

    drawObjectiveCallout()
    drawDebugInputPrompts()
    drawDebugText()
  }

  func drawObjectiveCallout() {
    callout.draw(in: Rect(x: 0, y: Float(HEIGHT) - 180, width: 520, height: 32))
  }

  func drawDebugInputPrompts() {
    if let prompts = InputPromptGroups.groups["Item Viewer"] {
      inputPrompts.drawHorizontal(
        prompts: prompts,
        inputSource: .keyboardMouse,
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        origin: (Float(WIDTH) - 56, 12),
        anchor: .bottomRight
      )
    }
  }

  func drawDebugText() {
    guard showDebugText else { return }

    let debugText = String(
      format: "%.1fx @ %@; %.1f; %.1f",
      camera.zoom, StringFromGLMathVec3(camera.position), camera.yaw, camera.pitch
    )

    debugText.draw(
      at: Point(24, Float(HEIGHT) - 24),
      style: determinationStyle,
      anchor: .topLeft
    )
  }
}
