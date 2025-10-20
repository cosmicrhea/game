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

///// The width of the game window in pixels.
//public let WIDTH = 1280 // 1800
///// The height of the game window in pixels.
//public let HEIGHT = 720 // 1126

/// Command-line interface options for the engine.
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
public final class Engine {
  public static let shared = Engine()
  public static func main() { shared.run() }

  // TODO: learn about Swift concurrency and how to use it correctly
  private nonisolated(unsafe) static var _cachedViewportSize: Size = Size(1280, 720)
  public nonisolated static var viewportSize: Size { return _cachedViewportSize }

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
    #if DEBUG
      print("|ω･)ﾉ♡☆ (debug)")
    #else
      print("|ω･)ﾉ♡☆")
    #endif

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
    window = try! GLFWWindow(width: 1280, height: 720, title: "")
    window.nsWindow?.styleMask.insert(.fullSizeContentView)
    window.nsWindow?.titlebarAppearsTransparent = true
    window.nsWindow?.toolbar = .init()
    //window.nsWindow?.hideStandardWindowButtons()
    //window.nsWindow?.darkenStandardWindowButtons()

    #if EDITOR
      editorHostingView = NSHostingView(rootView: EditorView())
      editorHostingView!.frame = NSRect(x: 0, y: 0, width: window.size.width, height: window.size.height)
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

    // Note: GLFW should automatically handle viewport updates, but we'll ensure it in beginFrame()
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
      ItemView(item: Item.allItems[1]),
      TitleScreenStack(),
      MainLoop(),
      MainMenu(),
      DocumentDemo(),
      // InventoryView(),
      // GradientDemo(),
      CreditsScreen(),
      // SVGDemo(),
      // SlotDemo(),
      // SlotGridDemo(),
      // LibraryView(),
      // MainMenu(),
      // CalloutDemo(),
      // PromptListDemo(),
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
    activeLoop.onAttach(window: window)

    // Schedule CLI actions relative to current time
    if cli.screenshot != nil { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
    if cli.exit { scheduleExitAt = GLFWSession.currentTime + 2.0 }
  }

  private func setupInputHandlers() {
    window.keyInputHandler = { [weak self] window, key, scancode, state, mods in
      guard let self = self else { return }
      self.activeLoop.onKey(window: window, key: key, scancode: Int32(scancode), state: state, mods: mods)
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
      self.activeLoop.onMouseButton(window: window, button: button, state: state, mods: mods)
      if state == .pressed {
        self.activeLoop.onMouseButtonPressed(window: window, button: button, mods: mods)
      } else if state == .released {
        self.activeLoop.onMouseButtonReleased(window: window, button: button, mods: mods)
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
  }

  private func runMainLoop() {
    while !window.shouldClose {
      let currentFrame = Float(GLFWSession.currentTime)
      deltaTime = currentFrame - lastFrame
      lastFrame = currentFrame

      activeLoop.update(window: window, deltaTime: deltaTime)

      Self._cachedViewportSize = Size(Float(window.size.width), Float(window.size.height))
      renderer.beginFrame(windowSize: Size(Float(window.size.width), Float(window.size.height)))

      GraphicsContext.withContext(graphicsContext) {
        activeLoop.draw()
      }

      // Draw screen fade in UI context so it always appears on top
      renderer.withUIContext {
        ScreenFadeFBO.shared.update(deltaTime: deltaTime)
        ScreenFadeFBO.shared.draw(screenSize: renderer.viewportSize)
      }

      renderer.endFrame()

      if let t = scheduleScreenshotAt, GLFWSession.currentTime >= t {
        requestScreenshot = true
        scheduleScreenshotAt = nil
      }

      if requestScreenshot {
        saveScreenshot(
          width: Int32(renderer.viewportSize.width), height: Int32(renderer.viewportSize.height), path: cli.screenshot)
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

#if os(macOS)
  import class AppKit.NSWindow
  import CoreImage.CIFilterBuiltins

  extension NSWindow {
    func hideStandardWindowButtons() {
      let buttonTypes: [ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
      for type in buttonTypes {
        guard let button = standardWindowButton(type) else { continue }
        button.isHidden = true
      }
    }

    func darkenStandardWindowButtons() {
      let filter = CIFilter.colorControls()
      filter.brightness = -0.4
      let buttonTypes: [ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
      for type in buttonTypes {
        guard let button = standardWindowButton(type) else { continue }
        button.wantsLayer = true
        button.layer?.filters = [filter]
        button.layer?.opacity = 0.6
      }
    }
  }
#endif
