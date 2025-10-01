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
window.setIcon(Image("icon~masked.webp"))
window.mouse.cursorMode = .disabled

var polygonMode = GL_FILL
var showDebugText = true
var requestScreenshot = false
var currentLoopIndex = 0
var loopCount = 0
var activeLoop: RenderLoop? = nil

// timing
var deltaTime: Float = 0.0
var lastFrame: Float = 0.0
var numberOfFrames: Int64 = 0
var lastTitleUpdate: Double = GLFWSession.currentTime

window.keyInputHandler = { window, key, scancode, state, mods in
  guard state == .pressed else { return }

  if let consumed = activeLoop?.onKey(window: window, key: key, scancode: Int32(scancode), state: state, mods: mods),
    consumed
  {
    return
  }

  if key == .comma {
    polygonMode = polygonMode == GL_FILL ? GL_LINE : GL_FILL
    UISound.select()
    return
  }
  if key == .backspace {
    showDebugText.toggle()
    UISound.select()
    return
  }
  if key == .p {
    requestScreenshot = true
    UISound.shutter()
    return
  }
  if key == .leftBracket || key == .rightBracket {
    currentLoopIndex =
      (key == .leftBracket)
      ? (currentLoopIndex - 1 + loopCount) % loopCount
      : (currentLoopIndex + 1) % loopCount

    activeLoop?.onDetach(window: window)
    if currentLoopIndex == 0 {
      activeLoop = nil
    } else {
      activeLoop = loops[currentLoopIndex - 1]
      activeLoop?.onAttach(window: window)
    }
    UISound.select()
    return
  }
}

var camera = FreeCamera()

@MainActor func processInput() {
  camera.processKeyboardState(window.keyboard, deltaTime)
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }
  if let consumed = activeLoop?.onMouseMove(window: window, x: x, y: y), consumed { return }
  camera.processMousePosition(Float(x), Float(y))
  ScreenEffect.mousePosition = (Float(x), Float(y))
}

window.scrollInputHandler = { window, xOffset, yOffset in
  if let consumed = activeLoop?.onScroll(window: window, xOffset: xOffset, yOffset: yOffset), consumed { return }
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

let fontRenderers: [(TextRenderer, FontLibrary.ResolvedFont)] = []

let loops: [RenderLoop] = [MainLoop(), CalloutDemo(), InputPromptsDemo(), FontsDemo()]
loopCount = loops.count + 1

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

  // Scene drawing moved to active RenderLoop

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

  // Active loop
  if currentLoopIndex != 0 { loops[currentLoopIndex - 1].update(deltaTime: deltaTime) }
  if currentLoopIndex != 0 { loops[currentLoopIndex - 1].draw() }

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

  // let groups: [InputPromptsRenderer.Row] = [
  //   .init(iconNames: ["mouse_move"], label: "Rotate"),
  //   .init(iconNames: ["mouse_scroll_vertical"], label: "Zoom"),
  //   .init(iconNames: ["keyboard_r"], label: "Reset"),
  //   .init(iconNames: ["keyboard_escape"], label: "Return"),
  // ]
  // //  let groups: [InputPromptsRenderer.Row] = [
  // //    .init(iconNames: ["xbox_stick_l"], label: "Rotate"),
  // //    .init(iconNames: ["xbox_stick_r_vertical"], label: "Zoom"),
  // //    .init(iconNames: ["xbox_button_color_x"], label: "Reset"),
  // //    .init(iconNames: ["xbox_button_color_b"], label: "Return"),
  // //  ]
  // // let groups: [InputPromptsRenderer.Row] = [
  // //   .init(iconNames: ["playstation_stick_l"], label: "Rotate"),
  // //   .init(iconNames: ["playstation_stick_r_vertical"], label: "Zoom"),
  // //   .init(iconNames: ["playstation_button_color_cross"], label: "Reset"),
  // //   .init(iconNames: ["playstation_button_color_circle"], label: "Return"),
  // // ]
  // inputPrompts.drawHorizontal(groups: groups, windowSize: (Int32(WIDTH), Int32(HEIGHT)))

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT))
    requestScreenshot = false
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
