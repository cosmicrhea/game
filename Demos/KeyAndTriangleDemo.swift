import Assimp

import class Foundation.Bundle

/// A demo that renders a triangle and a key.
@MainActor
final class KeyAndTriangleDemo: RenderLoop {

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
  /// Callout UI component for displaying hints.
  private var callout = Callout("Make your way to Kastellet", icon: .chevron)
  /// Input prompts component for controller/keyboard icons.
  private let promptList: PromptList

  // State
  private var objectiveVisible: Bool = true
  private var showDebugText: Bool = false

  /// The main shader program for rendering.
  private let program = try! GLProgram("Common/basic 2")

  init() {
    //let scenePath = Bundle.module.path(forResource: "Scenes/cabin_interior", ofType: "glb")!
    //    let scenePath = Bundle.module.path(forResource: "Items/old_key", ofType: "glb")!
    //    let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure, .calcTangentSpace])
    //    print("\(scene.rootNode)")
    //
    //    meshInstances = scene.meshes
    //      .filter { $0.numberOfVertices > 0 }
    //      .map { mesh in
    //        let transformMatrix = scene.getTransformMatrix(for: mesh)
    //        return MeshInstance(scene: scene, mesh: mesh, transformMatrix: transformMatrix)
    //      }

    meshInstances = []

    promptList = PromptList(.itemView, axis: .horizontal)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    guard window.isFocused else { return }
    camera.processMousePosition(Float(x), Float(y))
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    camera.processMouseScroll(Float(yOffset))
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
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

  func update(window: Window, deltaTime: Float) {
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
    let lightDirection = normalize(vec3(0.5, -1.0, 0.3))
    let lightColor = vec3(1.0, 1.0, 1.0)
    let lightIntensity: Float = 1.0

    meshInstances.forEach { meshInstance in
      meshInstance.draw(
        projection: GLMath.perspective(camera.zoom, 1, 0.001, 1000.0),
        view: camera.getViewMatrix(),
        cameraPosition: camera.position,
        lightDirection: lightDirection,
        lightColor: lightColor,
        lightIntensity: lightIntensity,
        fillLightDirection: vec3(-0.3, -0.5, -0.2),  // Simple fill light
        fillLightColor: vec3(0.8, 0.9, 1.0),
        fillLightIntensity: 1.0
      )
    }

    drawObjectiveCallout()
    drawDebugPromptList()
    drawDebugText()
  }

  func drawObjectiveCallout() {
    callout.draw()
  }

  func drawDebugPromptList() {
    promptList.draw()
  }

  func drawDebugText() {
    guard showDebugText else { return }

    let debugText = String(
      format: "%.1fx @ %@; %.1f; %.1f",
      camera.zoom, StringFromGLMathVec3(camera.position), camera.yaw, camera.pitch
    )

    debugText.draw(
      at: Point(24, Float(Engine.viewportSize.height) - 24),
      style: .itemDescription,
      anchor: .topLeft
    )
  }
}
