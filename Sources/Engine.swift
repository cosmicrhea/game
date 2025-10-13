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

/// The width of the game window in pixels.
public let WIDTH = 1280
/// The height of the game window in pixels.
public let HEIGHT = 720

/// Command-line interface options for the Glass engine.
struct CLIOptions: ParsableArguments {
  @Option(help: "Select demo by name, e.g. fonts, physics.")
  var demo: String?

  @Option(help: "Take a screenshot after 1 second. Optionally specify a path to save the screenshot.")
  var screenshot: String?

  @Flag(help: "Exit after 2 seconds.")
  var exit: Bool = false

  #if canImport(Darwin)
    @Flag(help: "Use Metal renderer instead of OpenGL on Apple platforms. (Unfinished.)")
    var metal: Bool = false
  #else
    let metal = false
  #endif
}

@main
@MainActor
final class Engine {
  static let shared = Engine()
  static func main() { shared.run() }

  private var config: Config { .current }

  private(set) var window: GLFWWindow!
  private(set) var activeLoop: RenderLoop!

  private(set) var renderer: Renderer!
  private(set) var graphicsContext: GraphicsContext!
  private(set) var loops: [RenderLoop] = []

  private var currentLoopIndex: Int = 0
  private var cli: CLIOptions!

  #if EDITOR
    private var editorHostingView: NSHostingView<EditorView>?
  #endif

  // State variables - these are now managed by config
  private var requestScreenshot = false
  private var scheduleScreenshotAt: Double? = nil
  private var scheduleExitAt: Double? = nil

  // Timing
  private var deltaTime: Float = 0.0
  private var lastFrame: Float = 0.0

  private init() {}

  private func run() {
    print(" 🥛 Glass Engine ")

    cli = CLIOptions.parseOrExit()

    setupLogging()
    setupGLFW()
    setupWindow()
    setupRenderer()
    setupLoops()
    setupInputHandlers()

    runMainLoop()
  }

  private func setupLogging() {
    LoggingSystem.bootstrap { OSLogHandler(label: $0) }
    sleep(1)  // ffs, apple… https://developer.apple.com/forums/thread/765445
  }

  private func setupGLFW() {
    GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }
    try! GLFWSession.initialize()

    GLFWWindow.hints.contextVersion = (4, 1)
    GLFWWindow.hints.openGLProfile = .core
    GLFWWindow.hints.openGLCompatibility = .forward
    GLFWWindow.hints.retinaFramebuffer = false
  }

  private func setupWindow() {
    window = try! GLFWWindow(width: WIDTH, height: HEIGHT, title: "")

    #if EDITOR
      editorHostingView = NSHostingView(rootView: EditorView())
      editorHostingView!.frame = NSRect(x: 0, y: 0, width: WIDTH, height: HEIGHT)
      editorHostingView!.autoresizingMask = [.minXMargin, .minYMargin, .height]
      editorHostingView!.isHidden = !config.editorEnabled
      window.nsWindow?.contentView?.addSubview(editorHostingView!)
    #endif

    window.position = .zero
    window.context.makeCurrent()
    window.setIcon(Image("UI/AppIcon/icon~masked.webp").glfwImage)

    let dotCursorImage = Image("UI/Cursors/dot_large.png").glfwImage
    let dotCursor = Mouse.Cursor.custom(
      dotCursorImage, center: GLFW.Point(dotCursorImage.width, dotCursorImage.height) / 2)
    window.mouse.setCursor(to: dotCursor)
  }

  private func setupRenderer() {
    renderer = {
      if cli.metal {
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

    graphicsContext = GraphicsContext(renderer: renderer, scale: 1)

    // Attach Metal layer to window if using Metal renderer
    if let metalRenderer = renderer as? MTLRenderer, let nsWindow = window.nsWindow {
      metalRenderer.attachToWindow(nsWindow)
    }

    // Initialize wireframe mode from config
    renderer.setWireframeMode(config.wireframeMode)
  }

  private func setupLoops() {
    loops = [
      SVGDemo(),

      MainLoop(),
      // SlotDemo(),
      SlotGridDemo(),
      TitleScreenStack(),  // Uses the new NavigationStack system
      //      LibraryView(),
      DocumentDemo(),
      MapView(),

      //      CalloutDemo(),
      //      PromptListDemo(),

      // FontsDemo(),
      // PathDemo(),
      // TextEffectsDemo(),
      // FadeDemo(),
    ]

    // Handle CLI demo selection
    if let demoArg = cli.demo?.lowercased() {
      if let found = loops.enumerated().first(where: { index, loop in
        let typeName = String(describing: type(of: loop)).lowercased()
        let normalized = typeName.replacingOccurrences(of: "demo", with: "")
        return typeName == demoArg || normalized == demoArg || typeName.contains(demoArg)
          || normalized.contains(demoArg)
      })?.offset {
        config.currentLoopIndex = found
      }
    }

    currentLoopIndex = config.currentLoopIndex
    activeLoop = loops[currentLoopIndex]
    //print("🎯 Running loop: \(type(of: activeLoop))")
    activeLoop.onAttach(window: window)

    // Schedule CLI actions relative to current time
    if cli.screenshot != nil { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
    if cli.exit { scheduleExitAt = GLFWSession.currentTime + 2.0 }
  }

  private func setupInputHandlers() {
    window.keyInputHandler = { [weak self] window, key, scancode, state, mods in
      guard let self = self else { return }
      if state == .pressed {
        self.activeLoop.onKeyPressed(window: window, key: key, scancode: Int32(scancode), mods: mods)
        handleGlobalDebugCommand(key: key)
      }
    }

    window.cursorPositionHandler = { [weak self] window, x, y in
      guard let self = self else { return }
      guard window.isFocused else { return }
      GLScreenEffect.mousePosition = (Float(x), Float(y))
      self.activeLoop.onMouseMove(window: window, x: x, y: y)
    }

    window.scrollInputHandler = { [weak self] window, xOffset, yOffset in
      guard let self = self else { return }
      self.activeLoop.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    }

    window.mouseButtonHandler = { [weak self] window, button, state, mods in
      guard let self = self else { return }
      if state == .pressed {
        self.activeLoop.onMouseButtonPressed(window: window, button: button, mods: mods)
      }
    }
  }

  private func handleGlobalDebugCommand(key: Keyboard.Key) {
    switch key {
    case .comma:
      UISound.select()
      config.wireframeMode.toggle()
      renderer.setWireframeMode(config.wireframeMode)

    case .p:
      UISound.shutter()
      requestScreenshot = true

    case .leftBracket:
      UISound.select()
      cycleLoops(-1)

    case .rightBracket:
      UISound.select()
      cycleLoops(+1)

    case .f19, .f9, .home:
      UISound.select()
      cycleInputSources()

    #if EDITOR
      case .backslash:
        UISound.select()
        config.editorEnabled.toggle()
        editorHostingView?.isHidden = !config.editorEnabled
    #endif

    default:
      break
    }
  }

  private func cycleLoops(_ step: Int) {
    let loopCount = loops.count
    currentLoopIndex = (currentLoopIndex + step + loopCount) % loopCount

    // Persist the change to config
    config.currentLoopIndex = currentLoopIndex

    activeLoop.onDetach(window: window)
    activeLoop = loops[currentLoopIndex]
    activeLoop.onAttach(window: window)

    // Reset screen fade when switching loops
    ScreenFadeFBO.shared.reset()

    // TODO: move this elsewhere; setting default clear color when changing loop
    //graphicsContext.renderer.setClearColor(Color(0.2, 0.1, 0.1, 1.0))

    #if EDITOR
      // Notify the editor that the loop has changed
      NotificationCenter.default.post(name: .loopChanged, object: nil)
    #endif
  }

  private func cycleInputSources() {
    let allSources = InputSource.allCases
    let currentIndex = allSources.firstIndex(of: InputSource.player1) ?? 0
    let nextIndex = (currentIndex + 1) % allSources.count
    InputSource.player1 = allSources[nextIndex]

    //print("🎮 InputSource.player1 switched to: \(InputSource.player1.rawValue)")
  }

  private func runMainLoop() {
    while !window.shouldClose {
      let currentFrame = Float(GLFWSession.currentTime)
      deltaTime = currentFrame - lastFrame
      lastFrame = currentFrame

      activeLoop.update(window: window, deltaTime: deltaTime)

      renderer.beginFrame(viewportSize: Size(Float(WIDTH), Float(HEIGHT)), scale: 1)

      GraphicsContext.withContext(graphicsContext) {
        activeLoop.draw()
      }

      // Draw screen fade in UI context so it always appears on top
      renderer.withUIContext {
        ScreenFadeFBO.shared.update(deltaTime: deltaTime)
        ScreenFadeFBO.shared.draw(screenSize: Size(Float(WIDTH), Float(HEIGHT)))
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
  }
}
