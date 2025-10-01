import Assimp
import Foundation
import GL
import GLFW
import GLMath

final class MainLoop: RenderLoop {
  private var window: GLFWWindow?

  // Scene and camera
  private var camera = FreeCamera()

  // Triangle demo
  private let testTriangle = TestTriangle()

  // Assimp mesh
  private let renderers: [MeshRenderer]

  // UI resources
  private let determination = TextRenderer("Determination", 32)!
  private let calloutRenderer = CalloutRenderer()
  private let calloutRenderer2 = CalloutRenderer()
  private let inputPrompts: InputPromptsRenderer
  private let chevron = ImageRenderer("UI/Icons/chevron.png")

  // Objective visibility state
  private var objectiveVisible: Bool = true

  private let program = try! GLProgram("Common/basic 2")

  init() {
    // Triangle geometry moved into TestTriangle

    // Load Assimp mesh
    let scenePath = Bundle.module.path(forResource: "Items/old_key", ofType: "glb")!
    let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
    print("\(scene.rootNode)")

    self.renderers = scene.meshes
      .filter { $0.numberOfVertices > 0 }
      .map { MeshRenderer(scene: scene, mesh: $0) }

    // Input prompts
    inputPrompts = InputPromptsRenderer()
  }

  @MainActor func onAttach(window: GLFWWindow) {
    self.window = window
  }

  @MainActor func onDetach(window: GLFWWindow) {
    self.window = nil
  }

  @MainActor func onMouseMove(window: GLFWWindow, x: Double, y: Double) -> Bool {
    guard window.isFocused else { return false }
    camera.processMousePosition(Float(x), Float(y))
    ScreenEffect.mousePosition = (Float(x), Float(y))
    return false
  }

  @MainActor func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) -> Bool {
    camera.processMouseScroll(Float(yOffset))
    return false
  }

  @MainActor func update(deltaTime: Float) {
    if let w = window { camera.processKeyboardState(w.keyboard, deltaTime) }
    // Update callout animation
    calloutRenderer.update(deltaTime: deltaTime)
  }

  @MainActor func toggleObjective() {
    objectiveVisible.toggle()
  }

  @MainActor func draw() {
    // Matrices
    let projection = GLMath.perspective(camera.zoom, 1, 0.001, 1000.0)
    let view = camera.getViewMatrix()

    program.use()
    program.setMat4("projection", value: projection)
    program.setMat4("view", value: view)
    program.setMat4("model", value: mat4(1))

    // Triangle
    testTriangle.draw()

    // Meshes
    renderers.forEach { $0.draw() }

    // Objective callout
    calloutRenderer.draw(
      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
      size: (520, 44),
      position: (0, Float(HEIGHT) - 180),
      anchor: .topLeft,
      fade: .right,
      icon: chevron,
      label: "Find the triangle and key",
      visible: objectiveVisible
    )

    //    // Input prompts callout
    //    calloutRenderer2.draw(
    //      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
    //      size: (Float(WIDTH), 80),
    //      position: (Float(WIDTH) - 520, -2),
    //      anchor: .bottomLeft,
    //      fade: .left,
    //    )

    //    // Input prompts (bottom-right horizontal strip)
    //    let groups: [InputPromptsRenderer.Row] = [
    //      .init(iconNames: ["mouse_move"], label: "Rotate"),
    //      .init(iconNames: ["mouse_scroll_vertical"], label: "Zoom"),
    //      .init(iconNames: ["keyboard_r"], label: "Reset"),
    //      .init(iconNames: ["keyboard_tab_icon"], label: "Close"),
    //    ]
    inputPrompts.drawHorizontal(
      prompts: InputPromptsRenderer.groups["Item Viewer"]!,
      inputSource: .keyboardMouse,
      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
      origin: (Float(WIDTH) - 32, 24),
      anchor: .bottomRight
    )

    // Debug label (top-left)
    let debugText = String(
      format: "%.1fx @ %@; %.1f; %.1f",
      camera.zoom, StringFromGLMathVec3(camera.position), camera.yaw, camera.pitch
    )
    determination.draw(
      debugText,
      at: (24, Float(HEIGHT) - 24),
      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
      anchor: .topLeft
    )
  }
}

// grapeSoda.draw(
//   "The quick brown fox jumps over the lazy dog", at: (100, 200),
//   windowSize: (Int32(WIDTH), Int32(HEIGHT)))

// determination.draw(
//   "The quick brown fox jumps over the lazy dog", at: (0, 0),
//   windowSize: (Int32(WIDTH), Int32(HEIGHT)))
// determination.draw(
//   "Quizdeltagerne spiste jordbær med fløde mens cirkusklovnen Walther spillede på xylofon",
//   at: (0, 64), windowSize: (Int32(WIDTH), Int32(HEIGHT)))

//  damageVignette.draw()
//  frostedVignette.draw()
//  gaussianBlur.draw()
// test.draw()

//  panel.draw()
