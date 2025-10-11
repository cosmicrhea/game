import ArgumentParser
import GL
import GLFW
import GLMath
import Logging
import unistd

#if EDITOR
  import SwiftUI
  import Foundation
#endif

//@_exported import Inject

/// The width of the game window in pixels.
let WIDTH = 1280
/// The height of the game window in pixels.
let HEIGHT = 720

/// Whether to prefer Metal rendering over OpenGL on Apple platforms.
let PREFER_METAL = false

print(" 🥛 Glass Engine ")

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

GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }
try! GLFWSession.initialize()

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward
GLFWWindow.hints.retinaFramebuffer = false
//GLFWWindow.hints.doubleBuffer = false
//GLFWWindow.hints.openGLDebugMode = true

let window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")

//window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.titlebarAppearsTransparent = true

#if EDITOR
  let editorHostingView = NSHostingView(rootView: EditorView())
  editorHostingView.frame = NSRect(x: 0, y: 0, width: 320, height: HEIGHT)
  editorHostingView.autoresizingMask = [.height, .minXMargin]
  window.nsWindow?.contentView?.addSubview(editorHostingView)
#endif

window.position = .zero
window.context.makeCurrent()
//window.context.setSwapInterval(0)
window.setIcon(Image("UI/AppIcon/icon~masked.webp").glfwImage)
//window.mouse.cursorMode = .disabled
let dotCursorImage = Image("UI/Cursors/dot_large.png").glfwImage
let dotCursor = Mouse.Cursor.custom(dotCursorImage, center: GLFW.Point(dotCursorImage.width, dotCursorImage.height) / 2)
window.mouse.setCursor(to: dotCursor)

var wireframeMode = false
var requestScreenshot = false
var scheduleScreenshotAt: Double? = nil
var scheduleExitAt: Double? = nil

var config: Config { .current }

let loops: [RenderLoop] = [
  //
  MainLoop(),
  MapView(),  // Move to front for testing
  LibraryView(),
  InputPromptsDemo(),
  //  AttributedTextDemo(),
  //  TextDemo(),
  // DocumentView(document: .operationGlasport),
  DocumentDemo(),
  CalloutDemo(),
  FontsDemo(),
  PathDemo(),
  TextEffectsDemo(),
  //  PhysicsDemo(),
  TitleScreen(),
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
print("🎯 Running loop: \(type(of: activeLoop))")
activeLoop.onAttach(window: window)

// Schedule CLI actions relative to current time
if cli.screenshot != nil { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
if cli.exit { scheduleExitAt = GLFWSession.currentTime + 2.0 }

@MainActor func cycleLoops(_ step: Int) {
  config.currentLoopIndex = (config.currentLoopIndex + step + loopCount) % loopCount
  activeLoop.onDetach(window: window)
  activeLoop = loops[config.currentLoopIndex]
  activeLoop.onAttach(window: window)
  // TODO: move this elsewhere; setting default clear color when changing loop
  GraphicsContext.current?.renderer.setClearColor(Color(0.2, 0.1, 0.1, 1.0))

  #if EDITOR
    // Notify the editor that the loop has changed
    NotificationCenter.default.post(name: .loopChanged, object: nil)
  #endif
}

// timing
var deltaTime: Float = 0.0
var lastFrame: Float = 0.0
var numberOfFrames: Int64 = 0

window.keyInputHandler = { window, key, scancode, state, mods in
  if state == .pressed {
    activeLoop.onKeyPressed(window: window, key: key, scancode: Int32(scancode), mods: mods)

    // Global debug commands
    switch key {
    case .comma:
      UISound.select()
      wireframeMode.toggle()
      renderer.setWireframeMode(wireframeMode)

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
}

window.cursorPositionHandler = { window, x, y in
  guard window.isFocused else { return }
  GLScreenEffect.mousePosition = (Float(x), Float(y))
  activeLoop.onMouseMove(window: window, x: x, y: y)
}

window.scrollInputHandler = { window, xOffset, yOffset in
  activeLoop.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
}

window.mouseButtonHandler = { window, button, state, mods in
  if state == .pressed {
    activeLoop.onMouseButtonPressed(window: window, button: button, mods: mods)
  }
}

let renderer: Renderer = {
  if PREFER_METAL {
    do {
      return try MTLRenderer()
    } catch {
      logger.warning("Failed to create Metal renderer, falling back to OpenGL: \(error)")
      return GLRenderer()
    }
  } else {
    return GLRenderer()
  }
}()

// Global graphics context
let graphicsContext = GraphicsContext(renderer: renderer, scale: 1)

// Attach Metal layer to window if using Metal renderer
if let metalRenderer = renderer as? MTLRenderer, let nsWindow = window.nsWindow {
  metalRenderer.attachToWindow(nsWindow)
}

while !window.shouldClose {
  let currentFrame = Float(GLFWSession.currentTime)
  deltaTime = currentFrame - lastFrame
  lastFrame = currentFrame

  activeLoop.update(window: window, deltaTime: deltaTime)

  renderer.beginFrame(viewportSize: Size(Float(WIDTH), Float(HEIGHT)), scale: 1)

  GraphicsContext.withContext(graphicsContext) {
    activeLoop.draw()
  }

  renderer.endFrame()

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
