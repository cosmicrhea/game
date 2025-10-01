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
  private let basicShading = try! GLProgram("Common/basic 2")
  private var vertexBuffer: GLuint = 0
  private var vertexArray: GLuint = 0

  // Assimp mesh (old_key)
  private let renderers: [MeshRenderer]

  // UI resources
  private let determination = TextRenderer("Determination", 32)!
  private let calloutRenderer = CalloutRenderer()
  private let promptsAtlas = AtlasImageRenderer("UI/InputPrompts/keyboard-mouse.xml")
  private let inputPrompts: InputPromptsRenderer
  private let arrowRight = ImageRenderer("UI/Arrows/curved-right.png")

  init() {
    // Triangle geometry
    let vertices: [Float] = [
      -0.5, -0.5, 0.0,
      0.5, -0.5, 0.0,
      0.0, 0.5, 0.0,
    ]
    glGenBuffers(1, &vertexBuffer)
    glGenVertexArrays(1, &vertexArray)
    glBindVertexArray(vertexArray)
    glBindBuffer(GL_ARRAY_BUFFER, vertexArray)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
    glVertexAttribPointer(
      index: 0, size: 3, type: GL_FLOAT, normalized: false,
      stride: GLsizei(3 * MemoryLayout<Float>.stride), pointer: nil
    )
    glEnableVertexAttribArray(0)

    // Load Assimp mesh
    let scenePath = Bundle.module.path(forResource: "Items/old_key", ofType: "glb")!
    let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
    self.renderers = scene.meshes
      .filter { $0.numberOfVertices > 0 }
      .map { MeshRenderer(scene: scene, mesh: $0) }

    // Input prompts
    inputPrompts = InputPromptsRenderer(atlas: promptsAtlas, labelFontName: "Creato Display Bold", labelPx: 28)
    inputPrompts.labelBaselineOffset = -16
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
  }

  @MainActor func draw() {
    // Triangle
    glBindVertexArray(vertexArray)
    basicShading.use()
    glDrawArrays(GL_TRIANGLES, 0, 3)

    // Matrices
    let projection = GLMath.perspective(camera.zoom, 1, 0.001, 1000.0)
    let view = camera.getViewMatrix()
    basicShading.setMat4("projection", value: projection)
    basicShading.setMat4("view", value: view)
    basicShading.setMat4("model", value: mat4(1))

    // Objective callout
    calloutRenderer.size = (520, 44)
    calloutRenderer.position = (0, Float(HEIGHT) - 180)
    calloutRenderer.anchor = .topLeft
    calloutRenderer.fade = .right
    calloutRenderer.label = "Find the triangle and key"
    calloutRenderer.icon = arrowRight
    calloutRenderer.iconSize = (24, 24)
    calloutRenderer.draw(windowSize: (Int32(WIDTH), Int32(HEIGHT)))

    // Meshes
    renderers.forEach { $0.draw() }

    // Input prompts (bottom-right horizontal strip)
    let groups: [InputPromptsRenderer.Row] = [
      .init(iconNames: ["mouse_move"], label: "Rotate"),
      .init(iconNames: ["mouse_scroll_vertical"], label: "Zoom"),
      .init(iconNames: ["keyboard_r"], label: "Reset"),
      .init(iconNames: ["keyboard_tab_icon"], label: "Return"),
    ]
    inputPrompts.drawHorizontal(groups: groups, windowSize: (Int32(WIDTH), Int32(HEIGHT)))

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
