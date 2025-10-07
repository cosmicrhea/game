import ArgumentParser
import Foundation
import GL
import GLFW
import GLMath
import Logging
import unistd

//@_exported import Inject

let WIDTH = 1280
let HEIGHT = 720

print(
  """
    
      ▄▀  █    ██      ▄▄▄▄▄    ▄▄▄▄▄         ▄▀  ██   █▀▄▀█ ▄███▄  
    ▄▀    █    █ █    █     ▀▄ █     ▀▄     ▄▀    █ █  █ █ █ █▀   ▀ 
    █ ▀▄  █    █▄▄█ ▄  ▀▀▀▀▄ ▄  ▀▀▀▀▄       █ ▀▄  █▄▄█ █ ▄ █ ██▄▄   
    █   █ ███▄ █  █  ▀▄▄▄▄▀   ▀▄▄▄▄▀        █   █ █  █ █   █ █▄   ▄▀
     ███      ▀   █                          ███     █    █  ▀███▀  
                 █                                  █    ▀          
                ▀                                  ▀                
  """
)

struct CLIOptions: ParsableArguments {
  @Option(help: "Select demo by name, e.g. fonts, physics.")
  var demo: String?

  @Flag(help: "Take a screenshot after 1 second.")
  var screenshot: Bool = false

  @Flag(help: "Exit after 2 second.")
  var exit: Bool = false
}

let cli = CLIOptions.parseOrExit()

//YourApp.main()

//#if DEBUG
//Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle")?.load()
//#endif

LoggingSystem.bootstrap { OSLogHandler(label: $0) }
sleep(1)  // ffs, apple… https://developer.apple.com/forums/thread/765445

try! GLFWSession.initialize()
GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward
GLFWWindow.hints.retinaFramebuffer = false

let window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")
//window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.titlebarAppearsTransparent = true
window.position = .zero
window.context.makeCurrent()
//window.context.setSwapInterval(0)
window.setIcon(Image("UI/AppIcon/icon~masked.webp"))
//window.mouse.cursorMode = .disabled
let dotCursorImage = Image("UI/Cursors/dot_large.png")
let dotCursor = Mouse.Cursor.custom(dotCursorImage, center: Point(dotCursorImage.width, dotCursorImage.height) / 2)
window.mouse.setCursor(to: dotCursor)

var polygonMode = GL_FILL
var showDebugText = true
var requestScreenshot = false
var scheduleScreenshotAt: Double? = nil
var scheduleExitAt: Double? = nil

var config: Config { .current }

let loops: [RenderLoop] = [
  //
  MainLoop(),
  InputPromptsDemo(),
  AttributedTextDemo(),
  TextDemo(),
  DocumentDemo(),
  CalloutDemo(),
  FontsDemo(),
  PhysicsDemo(),
]

var loopCount = loops.count
//var currentLoopIndex = 0
if let demoArg = cli.demo?.lowercased() {
  if let found = loops.enumerated().first(where: { index, loop in
    let typeName = String(describing: type(of: loop)).lowercased()
    let normalized = typeName.replacingOccurrences(of: "demo", with: "")
    return typeName == demoArg || normalized == demoArg || typeName.contains(demoArg) || normalized.contains(demoArg)
  })?.offset {
    config.currentLoopIndex = found
  }
}
var activeLoop: RenderLoop = loops[config.currentLoopIndex]
activeLoop.onAttach(window: window)

// Schedule CLI actions relative to current time
if cli.screenshot { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
if cli.exit { scheduleExitAt = GLFWSession.currentTime + 2.0 }

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

  if let t = scheduleScreenshotAt, GLFWSession.currentTime >= t {
    requestScreenshot = true
    scheduleScreenshotAt = nil
  }

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT))
    requestScreenshot = false
  }

  if let t = scheduleExitAt, GLFWSession.currentTime >= t {
    break
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
