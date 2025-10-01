import Assimp
import Foundation
import GL
import GLFW
import GLMath
import ImageFormats
import Logging
import LoggingOSLog
import unistd

typealias glm = GLMath

let WIDTH = 1280
let HEIGHT = 720

//YourApp.main()

LoggingSystem.bootstrap { LoggingOSLog(label: $0) }
sleep(1)  // ffs, apple… https://developer.apple.com/forums/thread/765445

try! GLFWSession.initialize()
GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward

let window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")
//window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.titlebarAppearsTransparent = true
window.position = .zero
window.context.makeCurrent()
//window.context.setSwapInterval(0)
window.setIcon(Image("icon~squircle.webp"))
window.mouse.cursorMode = .disabled

var polygonMode = GL_FILL
var showDebugText = true
var requestScreenshot = false
var currentDemoIndex = 0
var demoCount = 0

// timing
var deltaTime: Float = 0.0
var lastFrame: Float = 0.0
var numberOfFrames: Int64 = 0
var lastTitleUpdate: Double = GLFWSession.currentTime

window.keyInputHandler = { _, key, _, state, _ in
  guard state == .pressed else { return }

  switch key {
  case .comma:
    polygonMode = polygonMode == GL_FILL ? GL_LINE : GL_FILL

  case .backspace:
    showDebugText.toggle()

  case .p:
    requestScreenshot = true
    UISound.shutter()
    return

  case .leftBracket:
    currentDemoIndex = (currentDemoIndex - 1 + demoCount) % demoCount

  case .rightBracket:
    currentDemoIndex = (currentDemoIndex + 1) % demoCount

  default:
    return
  }

  UISound.select()
}

var camera = FreeCamera()

@MainActor func processInput() {
  camera.processKeyboardState(window.keyboard, deltaTime)
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }
  camera.processMousePosition(Float(x), Float(y))
  ScreenEffect.mousePosition = (Float(x), Float(y))
}

window.scrollInputHandler = { _, _, yOffset in
  camera.processMouseScroll(Float(yOffset))
}

glEnable(GL_DEPTH_TEST)

let basicShading = try! GLProgram("Common/basic 2")

let vertices: [Float] = [
  -0.5, -0.5, 0.0,
  0.5, -0.5, 0.0,
  0.0, 0.5, 0.0,
]

var vertexBuffer = GLuint()
glGenBuffers(1, &vertexBuffer)

var vertexArray = GLuint()
glGenVertexArrays(1, &vertexArray)

glBindVertexArray(vertexArray)
glBindBuffer(GL_ARRAY_BUFFER, vertexArray)
glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
glVertexAttribPointer(
  index: 0, size: 3, type: GL_FLOAT, normalized: false,
  stride: GLsizei(3 * MemoryLayout<Float>.stride), pointer: nil
)
//glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)
glEnableVertexAttribArray(0)

let scenePath = Bundle.module.path(forResource: "Items/old_key", ofType: "glb")!

let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
print("\(scene.rootNode)")

let renderers = scene.meshes
  .filter { $0.numberOfVertices > 0 }
  .map { MeshRenderer(scene: scene, mesh: $0) }

let grapeSoda = TextRenderer("Grape Soda")!
//let determination = TextRenderer("Determination", 64)!
let determination = TextRenderer("Determination", 32)!
let ari = TextRenderer("Ari-W9500 Bold", 32)!

let fontRenderers: [(TextRenderer, FontLibrary.ResolvedFont)] = FontLibrary.availableFonts
  .compactMap { resolvedFont -> (TextRenderer, FontLibrary.ResolvedFont)? in
    guard let renderer = TextRenderer(resolvedFont.displayName) else { return nil }
    return (renderer, resolvedFont)
  }

let gaussianBlur = ScreenEffect("effects/gaussian_blur")
let frostedVignette = ScreenEffect("effects/frosted_vignette")
let simpleVignette = ScreenEffect("effects/simple_vignette")
let damageVignette = ScreenEffect("effects/damage_vignette")
let test = ScreenEffect("effects/liquid_glass")
let panel = ScreenEffect("effects/panel")
let callout = ScreenEffect("effects/callout")
let calloutRenderer = CalloutRenderer()
//let gaussian_blur = ScreenEffect("effects/gaussian_blur")

let arrowRight = ImageRenderer("UI/Arrows/curved-right.png")
// let promptsAtlas = AtlasImageRenderer("UI/InputPrompts/playstation.xml")
//let promptsAtlas = AtlasImageRenderer("UI/InputPrompts/xbox.xml")
let promptsAtlas = AtlasImageRenderer("UI/InputPrompts/keyboard-mouse.xml")
let inputPrompts = InputPromptsRenderer(atlas: promptsAtlas, labelFontName: "Creato Display Bold", labelPx: 28)
inputPrompts.labelBaselineOffset = -16

// Demo scenes are now proper types under `Sources/Demos`
let demoScenes: [Demo] = [CalloutDemo(), InputPromptsDemo(), FontsDemo()]
demoCount = demoScenes.count + 1  // include 'no demo' state at index 0

while !window.shouldClose {
  let currentFrame = Float(GLFWSession.currentTime)
  deltaTime = currentFrame - lastFrame
  lastFrame = currentFrame

  //  // FPS in window title (update ~once per second)
  //  numberOfFrames += 1
  //  let now = GLFWSession.currentTime
  //  let elapsed = now - lastTitleUpdate
  //  if elapsed >= 1.0 {
  //    let fps = Double(numberOfFrames) / elapsed
  //    window.nsWindow?.title = String(format: "FPS: %.0f", fps)
  //    numberOfFrames = 0
  //    lastTitleUpdate = now
  //  }

  processInput()

  glClearColor(0.2, 0.1, 0.1, 1)
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

  //print(GLFWSession.currentTime)

  //    var model = mat4(1)
  //    model = glm.translate(model, vec3())
  //    model = glm.rotate(model, radians(20.0), vec3(1, 0.3, 0.5))

  glPolygonMode(GL_FRONT_AND_BACK, polygonMode)

  basicShading.use()
  glBindVertexArray(vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)

  // pass projection matrix to shader (note that in this case it could change every frame)
  let projection = GLMath.perspective(camera.zoom, 1, 0.001, 1000.0)

  // camera/view transformation
  let view = camera.getViewMatrix()

  basicShading.setMat4("projection", value: projection)
  basicShading.setMat4("view", value: view)
  basicShading.setMat4("model", value: mat4(1))

  renderers.forEach { $0.draw() }

  // grapeSoda.draw(
  //   "The quick brown fox jumps over the lazy dog", at: (100, 200),
  //   windowSize: (Int32(WIDTH), Int32(HEIGHT)))

  // determination.draw(
  //   "The quick brown fox jumps over the lazy dog", at: (0, 0),
  //   windowSize: (Int32(WIDTH), Int32(HEIGHT)))
  // determination.draw(
  //   "Quizdeltagerne spiste jordbær med fløde mens cirkusklovnen Walther spillede på xylofon",
  //   at: (0, 64), windowSize: (Int32(WIDTH), Int32(HEIGHT)))

  // var yCursor: Float = 24
  // for (renderer, resolvedFont) in fontRenderers {
  //   // Treat yCursor as the baseline position. Move down to the baseline first,
  //   // then draw, then add descender + padding for the next line.
  //   yCursor += renderer.baselineFromTop
  //   renderer.draw(
  //     //resolvedFont.baseName + ": The quick brown fox jumps over the lazy dog",
  //     resolvedFont.baseName + ": triangle is the key",
  //     at: (24, yCursor),
  //     windowSize: (Int32(WIDTH), Int32(HEIGHT))
  //   )
  //   yCursor += renderer.descentFromBaseline + 8
  // }

  //  damageVignette.draw()
  //  frostedVignette.draw()
  //  gaussianBlur.draw()
  // test.draw()

  //  panel.draw()

  // Callouts via renderer
  do {
    // First callout
    calloutRenderer.size = (520, 44)
    calloutRenderer.position = (0, Float(HEIGHT) - 180)
    calloutRenderer.anchor = .topLeft
    calloutRenderer.fade = .right
    calloutRenderer.label = "Find the triangle and key"
    calloutRenderer.icon = arrowRight
    calloutRenderer.iconSize = (24, 24)
    calloutRenderer.draw(windowSize: (Int32(WIDTH), Int32(HEIGHT)))

    //    // Second, taller callout below
    //    calloutRenderer.size = (520, 96)
    //    calloutRenderer.position = (0, Float(HEIGHT) - 180 - 44 - 12)
    //    calloutRenderer.anchor = .topLeft
    //    calloutRenderer.fade = .right
    //    calloutRenderer.label = "Find the key in the storage room"
    //    calloutRenderer.icon = arrowRight
    //    calloutRenderer.iconSize = (32, 32)
    //    calloutRenderer.draw(windowSize: (Int32(WIDTH), Int32(HEIGHT)))
  }
  //  img.draw(x: 100, y: 100, windowSize: (Int32(WIDTH), Int32(HEIGHT)), opacity: 0.5)

  // Active demo scene if selected (index 1..N)
  if currentDemoIndex != 0 {
    demoScenes[currentDemoIndex - 1].draw()
  }

  // let prompts = [
  //   "Rotate": [
  //     ["mouse_move"],
  //     ["xbox_stick_l"],
  //     ["playstation_stick_l"],
  //   ],
  //   "Zoom": [
  //     ["mouse_scroll_vertical"],
  //     ["xbox_stick_r_vertical"],
  //     ["playstation_stick_r_vertical"],
  //   ],
  //   "Reset": [
  //     ["keyboard_r"],
  //     ["xbox_button_color_x"],
  //     ["playstation_button_color_cross"],
  //   ],
  //   "Return": [
  //     ["keyboard_escape"],
  //     ["xbox_button_color_b"],
  //     ["playstation_button_color_circle"],
  //   ],
  // ]

  let groups: [InputPromptsRenderer.Row] = [
    .init(iconNames: ["mouse_move"], label: "Rotate"),
    .init(iconNames: ["mouse_scroll_vertical"], label: "Zoom"),
    .init(iconNames: ["keyboard_r"], label: "Reset"),
    .init(iconNames: ["keyboard_escape"], label: "Return"),
  ]
  //  let groups: [InputPromptsRenderer.Row] = [
  //    .init(iconNames: ["xbox_stick_l"], label: "Rotate"),
  //    .init(iconNames: ["xbox_stick_r_vertical"], label: "Zoom"),
  //    .init(iconNames: ["xbox_button_color_x"], label: "Reset"),
  //    .init(iconNames: ["xbox_button_color_b"], label: "Return"),
  //  ]
  // let groups: [InputPromptsRenderer.Row] = [
  //   .init(iconNames: ["playstation_stick_l"], label: "Rotate"),
  //   .init(iconNames: ["playstation_stick_r_vertical"], label: "Zoom"),
  //   .init(iconNames: ["playstation_button_color_cross"], label: "Reset"),
  //   .init(iconNames: ["playstation_button_color_circle"], label: "Return"),
  // ]
  inputPrompts.drawHorizontal(groups: groups, windowSize: (Int32(WIDTH), Int32(HEIGHT)))

  if showDebugText {
    let debugText = """
      \(String(format: "%.1f", camera.zoom))x @ \(camera.position); \(String(format: "%.1f", camera.yaw)); \(String(format: "%.1f", camera.pitch))
      """

    determination.draw(
      debugText,
      at: (24, Float(HEIGHT) - 24),
      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
      anchor: .topLeft
    )
  }

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT))
    requestScreenshot = false
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
