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
  private let renderers: [MeshRenderer]

  // UI resources
  /// Text renderer using the Determination font.
  private let determination = TextRenderer("Determination", 32)!
  /// Callout UI component for displaying hints.
  private var callout = Callout("Find the triangle and key", icon: .chevron)
  /// Input prompts component for controller/keyboard icons.
  private let inputPrompts: InputPrompts
  /// Renderer for both 2D and 3D content.
  private let renderer: Renderer

  // State
  private var objectiveVisible: Bool = true
  private var showDebugText: Bool = false

  /// The main shader program for rendering.
  private let program = try! GLProgram("Common/basic 2")

  /// Initializes the main loop with scene data and renderers.
  init() {
    // Initialize Metal renderer
    do {
      self.renderer = try MTLRenderer()
    } catch {
      print("Failed to create Metal renderer, falling back to OpenGL: \(error)")
      self.renderer = GLRenderer()
    }
    let scenePath = Bundle.module.path(forResource: "Scenes/cabin_interior", ofType: "glb")!
    let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
    print("\(scene.rootNode)")

    renderers = scene.meshes
      .filter { $0.numberOfVertices > 0 }
      .map { MeshRenderer(scene: scene, mesh: $0) }

    inputPrompts = InputPrompts()
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) -> Bool {
    guard window.isFocused else { return false }
    camera.processMousePosition(Float(x), Float(y))
    GLScreenEffect.mousePosition = (Float(x), Float(y))
    return true
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) -> Bool {
    camera.processMouseScroll(Float(yOffset))
    return true
  }

  func onKey(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier)
    -> Bool
  {
    guard state == .pressed else { return false }

    switch key {
    case .o:
      UISound.select()
      toggleObjective()

    case .backspace:
      UISound.select()
      showDebugText.toggle()

    default:
      return false
    }

    return true
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
    renderers.forEach { $0.draw() }

    drawObjectiveCallout()
    //drawDebugInputPrompts()
    drawDebugText()
  }

  func drawObjectiveCallout() {
    callout.draw(in: Rect(x: 0, y: Float(HEIGHT) - 180, width: 520, height: 44))
  }

  func drawDebugInputPrompts() {
    // Set up rendering context
    renderer.beginFrame(viewportSize: Size(Float(WIDTH), Float(HEIGHT)), scale: 1)
    let ctx = GraphicsContext(renderer: renderer, scale: 1)
    GraphicsContext.withContext(ctx) {
      // Draw input prompts for the current group (Item Pickup as example)
      if let itemPickupPrompts = InputPromptGroups.groups["Item Pickup"] {
        inputPrompts.drawHorizontal(
          prompts: itemPickupPrompts,
          inputSource: .keyboardMouse,
          windowSize: (Int32(WIDTH), Int32(HEIGHT)),
          origin: (Float(WIDTH) - 32, 24),
          anchor: .bottomRight
        )
      }
    }
    renderer.endFrame()
  }

  func drawDebugText() {
    guard showDebugText else { return }

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
