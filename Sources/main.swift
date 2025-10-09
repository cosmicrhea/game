import ArgumentParser
import GL
import GLFW
import GLMath
import Logging
import unistd

//@_exported import Inject

/// The width of the game window in pixels.
let WIDTH = 1280
/// The height of the game window in pixels.
let HEIGHT = 720

print(" 🥛 Glass Engine ")
logger.info("yeet!")

/// Command-line interface options for the Glass engine.
struct CLIOptions: ParsableArguments {
  @Option(help: "Select demo by name, e.g. fonts, physics.")
  var demo: String?

  @Option(help: "Take a screenshot after 1 second. Optionally specify a path to save the screenshot.")
  var screenshot: String?

  @Flag(help: "Exit after 2 seconds.")
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
//GLFWWindow.hints.doubleBuffer = false
//GLFWWindow.hints.openGLDebugMode = true

let window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")
//window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.titlebarAppearsTransparent = true
window.position = .zero
window.context.makeCurrent()
//window.context.setSwapInterval(0)
window.setIcon(Image(resourcePath: "UI/AppIcon/icon~masked.webp").glfwImage)
//window.mouse.cursorMode = .disabled
let dotCursorImage = GLFW.Image("UI/Cursors/dot_large.png")
let dotCursor = Mouse.Cursor.custom(dotCursorImage, center: GLFW.Point(dotCursorImage.width, dotCursorImage.height) / 2)
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
  //  AttributedTextDemo(),
  //  TextDemo(),
  DocumentDemo(),
  CalloutDemo(),
  FontsDemo(),
  PathDemo(),
  //  PhysicsDemo(),
]

var loopCount = loops.count

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
if cli.screenshot != nil { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
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

  default:
    break
  }
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }
  if activeLoop.onMouseMove(window: window, x: x, y: y) { return }
}

window.scrollInputHandler = { window, xOffset, yOffset in
  if activeLoop.onScroll(window: window, xOffset: xOffset, yOffset: yOffset) { return }
}

glEnable(GL_DEPTH_TEST)

let grapeSoda = TextRenderer("Grape Soda")!
//let determination = TextRenderer("Determination", 64)!
let determination = TextRenderer("Determination", 32)!
let ari = TextRenderer("Ari-W9500 Bold", 32)!

// Global 2D renderer for UI elements
let gl2DRenderer = GLRenderer()

while !window.shouldClose {
  let currentFrame = Float(GLFWSession.currentTime)
  deltaTime = currentFrame - lastFrame
  lastFrame = currentFrame

  // All per-frame input is handled by the active loop's update(window:deltaTime:)

  glClearColor(0.2, 0.1, 0.1, 1)
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
  glPolygonMode(GL_FRONT_AND_BACK, polygonMode)

  // Active loop
  activeLoop.update(window: window, deltaTime: deltaTime)

  // Set up global GraphicsContext for UI rendering
  gl2DRenderer.beginFrame(viewportSize: Size(Float(WIDTH), Float(HEIGHT)), scale: 1)
  let graphicsContext = GraphicsContext(renderer: gl2DRenderer, scale: 1)
  GraphicsContext.withContext(graphicsContext) {
    activeLoop.draw()
  }
  gl2DRenderer.endFrame()

  if let t = scheduleScreenshotAt, GLFWSession.currentTime >= t {
    requestScreenshot = true
    scheduleScreenshotAt = nil
  }

  if requestScreenshot {
    saveScreenshot(width: Int32(WIDTH), height: Int32(HEIGHT), path: cli.screenshot)
    requestScreenshot = false
  }

  if let t = scheduleExitAt, GLFWSession.currentTime >= t {
    break
  }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
