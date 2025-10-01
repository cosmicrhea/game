import Foundation
import GL
import GLFW
import GLMath
import ImageFormats
import Logging
import LoggingOSLog
import unistd
@_exported import Inject

let WIDTH = 1280
let HEIGHT = 720

//YourApp.main()

#if DEBUG
Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
#endif

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

var config: Config { .current }

// Render loop selection (no null state)
let loops: [RenderLoop] = [
  //
  MainLoop(),
  //CalloutDemo(),
  InputPromptsDemo(),
  FontsDemo()
]
var loopCount = loops.count
//var currentLoopIndex = 0
var activeLoop: RenderLoop = loops[config.currentLoopIndex]
activeLoop.onAttach(window: window)

@MainActor func cycleLoops(_ step: Int) {
  config.currentLoopIndex = (config.currentLoopIndex + step + loopCount) % loopCount
  activeLoop.onDetach(window: window)
  activeLoop = loops[config.currentLoopIndex]
  activeLoop.onAttach(window: window)
}

// timing
var deltaTime: Float = 0.0
var lastFrame: Float = 0.0
var numberOfFrames: Int64 = 0
var lastTitleUpdate: Double = GLFWSession.currentTime

window.keyInputHandler = { window, key, scancode, state, mods in
  guard state == .pressed else { return }

  if activeLoop.onKey(window: window, key: key, scancode: Int32(scancode), state: state, mods: mods) { return }

  switch key {
  case .comma:
    UISound.select()
    polygonMode = polygonMode == GL_FILL ? GL_LINE : GL_FILL

  case .backspace:
    UISound.select()
    showDebugText.toggle()

  case .p:
    UISound.shutter()
    requestScreenshot = true

  case .leftBracket:
    UISound.select()
    cycleLoops(-1)

  case .rightBracket:
    UISound.select()
    cycleLoops(+1)

  case .o:
    if let mainLoop = activeLoop as? MainLoop {
      mainLoop.toggleObjective()
    }

  default:
    break
  }
}

var camera = FreeCamera()

@MainActor func processInput() {
  camera.processKeyboardState(window.keyboard, deltaTime)
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }
  if activeLoop.onMouseMove(window: window, x: x, y: y) { return }
  camera.processMousePosition(Float(x), Float(y))
  ScreenEffect.mousePosition = (Float(x), Float(y))
}

window.scrollInputHandler = { window, xOffset, yOffset in
  if activeLoop.onScroll(window: window, xOffset: xOffset, yOffset: yOffset) { return }
  camera.processMouseScroll(Float(yOffset))
}

glEnable(GL_DEPTH_TEST)

let grapeSoda = TextRenderer("Grape Soda")!
//let determination = TextRenderer("Determination", 64)!
let determination = TextRenderer("Determination", 32)!
let ari = TextRenderer("Ari-W9500 Bold", 32)!

while !window.shouldClose {
  let currentFrame = Float(GLFWSession.currentTime)
  deltaTime = currentFrame - lastFrame
  lastFrame = currentFrame

  processInput()

  glClearColor(0.2, 0.1, 0.1, 1)
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
  glPolygonMode(GL_FRONT_AND_BACK, polygonMode)

  // Active loop
  activeLoop.update(deltaTime: deltaTime)
  activeLoop.draw()

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT))
    requestScreenshot = false
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
