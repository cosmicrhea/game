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

LoggingSystem.bootstrap(LoggingOSLog.init)
sleep(1)  // ffs, apple… https://developer.apple.com/forums/thread/765445

try! GLFWSession.initialize()
GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward

let window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")
window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.titlebarAppearsTransparent = true
window.position = .zero
window.context.makeCurrent()
//window.context.setSwapInterval(0)
window.mouse.cursorMode = .disabled

var polygonMode = GL_FILL
var requestScreenshot = false

// timing
var deltaTime: Float = 0.0
var lastFrame: Float = 0.0
var numberOfFrames: Int64 = 0
var lastTitleUpdate: Double = GLFWSession.currentTime

window.keyInputHandler = { _, key, _, state, _ in
  if key == .comma && state == .pressed {
    UISound.select()
    polygonMode = polygonMode == GL_FILL ? GL_LINE : GL_FILL
  }
  if key == .p && state == .pressed {
    UISound.shutter()
    requestScreenshot = true
  }
}

var lastX = Double(WIDTH) / 2.0
var lastY = Double(HEIGHT) / 2.0
var firstMouse = true

var camera = FreeCamera()

@MainActor func processInput() {
  if window.keyboard.state(of: .w) == .pressed {
    camera.processKeyboard(.forward, deltaTime: deltaTime)
  }
  if window.keyboard.state(of: .s) == .pressed {
    camera.processKeyboard(.backward, deltaTime: deltaTime)
  }
  if window.keyboard.state(of: .a) == .pressed {
    camera.processKeyboard(.left, deltaTime: deltaTime)
  }
  if window.keyboard.state(of: .d) == .pressed {
    camera.processKeyboard(.right, deltaTime: deltaTime)
  }
  if window.keyboard.state(of: .q) == .pressed { camera.processKeyboard(.up, deltaTime: deltaTime) }
  if window.keyboard.state(of: .e) == .pressed {
    camera.processKeyboard(.down, deltaTime: deltaTime)
  }
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }

  let xpos = x
  let ypos = y

  if firstMouse {
    lastX = xpos
    lastY = ypos
    firstMouse = false
    return
  }

  let xoffset = xpos - lastX
  let yoffset = lastY - ypos  // reversed since y-coordinates go from bottom to top

  lastX = xpos
  lastY = ypos

  // logger.info("offsets: \(xoffset), \(yoffset)")
  camera.processMouseMovement(xOffset: Float(xoffset), yOffset: Float(yoffset))
}

window.scrollInputHandler = { _, _, yOffset in
  // logger.info("yOffset: \(yOffset)")
  camera.processMouseScroll(Float(yOffset))
}

glEnable(GL_DEPTH_TEST)

let basicShading = try! GLProgram("common/basic 2")

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

let scenePath = Bundle.module.path(forResource: "inventory/old_key", ofType: "glb")!

let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
print("\(scene.rootNode)")

let renderers = scene.meshes
  .filter { $0.numberOfVertices > 0 }
  .map { MeshRenderer(scene: scene, mesh: $0) }

let grapeSoda = TextRenderer("Grape Soda")!
let determination = TextRenderer("Determination", 64)!

let fontRenderers: [(TextRenderer, FontLibrary.ResolvedFont)] = FontLibrary.availableFonts
  .compactMap { resolvedFont -> (TextRenderer, FontLibrary.ResolvedFont)? in
    guard let renderer = TextRenderer(resolvedFont.displayName) else { return nil }
    return (renderer, resolvedFont)
  }

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
  basicShading.setMat4("projection", value: projection)

  // camera/view transformation
  let view = camera.getViewMatrix()
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

  var yCursor: Float = 0
  for (renderer, resolvedFont) in fontRenderers {
    let pixelHeight = Float(resolvedFont.pixelSize ?? 16)
    yCursor += pixelHeight
    renderer.draw(
      resolvedFont.baseName,
      at: (8, yCursor),
      windowSize: (Int32(WIDTH), Int32(HEIGHT))
    )
    yCursor += 10
  }

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT))
    requestScreenshot = false
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
