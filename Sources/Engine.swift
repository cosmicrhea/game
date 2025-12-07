import ArgumentParser
import Logging
import unistd

#if canImport(AppKit)
  import AppKit
#endif

let DESIGN_RESOLUTION = Size(1280, 800)
//let DESIGN_RESOLUTION = Size(1920, 1200)
//let DESIGN_RESOLUTION = Size(1800, 1126)

let VIEWPORT_SCALING = false

let TWO_PLAYER_MODE = false

struct CLIOptions: ParsableArguments {
  @Option(help: "Select demo by name, e.g. fonts, physics.")
  var demo: String?

  @Option(help: "Take a screenshot after 1 second. Optionally specify a path to save the screenshot.")
  var screenshot: String?

  @ArgumentParser.Flag(help: "Exit after 2 seconds.")
  var exit: Bool = false

  #if canImport(Metal)
    @ArgumentParser.Flag(help: "Use Metal renderer instead of OpenGL on supported platforms. (Unfinished.)")
    var metal: Bool = false
  #else
    let metal = false
  #endif
}

extension Bundle {
  static let game = Bundle(path: main.resourcePath! + "/Contents/Resources") ?? #bundle
}

@main
@MainActor
public final class Engine {
  public static let shared = Engine()

  // TODO: learn about Swift concurrency and how to use it correctly
  private nonisolated(unsafe) static var _cachedViewportSize: Size = DESIGN_RESOLUTION
  public nonisolated static var viewportSize: Size { return _cachedViewportSize }

  private var config: Config { .current }

  private(set) var window: GLFWWindow!
  private(set) var editorWindow: GLFWWindow!
  private(set) var activeLoop: RenderLoop!

  private(set) var renderer: Renderer!
  private(set) var graphicsContext: GraphicsContext!
  private(set) var loops: [RenderLoop] = []

  private var currentLoopIndex: Int = 0
  private var cli: CLIOptions!

  // Editor system
  private var editorPanel: EditorPanel!
  private var editorRenderer: Renderer!
  private var editorGraphicsContext: GraphicsContext!
  // Editor background effect (created lazily after a GL context is current)
  private var editorAmbientBackground: GLScreenEffect? = nil

  // State variables
  private var requestScreenshot = false
  private var scheduleScreenshotAt: Double? = nil
  private var scheduleExitAt: Double? = nil
  private var showStats = false

  // Timing
  private var deltaTime: Float = 0.0
  private var lastFrame: Float = 0.0
  private var lastTitleUpdateTime: Double = 0.0
  private var targetFrameTime: Double = 1.0 / 60.0  // Target 60 FPS
  private var lastFrameTime: Double = 0.0

  //private init() {}

  public static func main() {
    shared.run()
  }

  public func run() {
    #if DEBUG
      print("|ω･)ﾉ♡☆ (debug)")
    #else
      print("|ω･)ﾉ♡☆")
    #endif

    print(Locale.game)

    //    print("Bundle.game: \(Bundle.game)")
    //    print("Bundle.main: \(Bundle.main)")
    //    print("Bundle.module: \(Bundle.module)")
    //    print("#bundle: \(#bundle)")

    //LoggingSystem.bootstrap { OSLogHandler(label: $0) }

    cli = CLIOptions.parseOrExit()

    setupGLFW()
    setupWindow()
    setupEditorWindow()
    setupRenderer()
    setupLoops()
    setupInputHandlers()

    // Respect config: keep editor visible on launch if enabled (ensure window is shown after all setup)
    if config.editorEnabled {
      config.editorEnabled = true
      editorWindow.show()
      // Bring focus if desired
      editorWindow.focus(force: true)
      updateEditorForCurrentLoop()
    } else {
      editorWindow.hide()
    }

    runMainLoop()
  }

  private func setupGLFW() {
    GLFWSession.onReceiveError = { error in logger.error("GLFW: \(error)") }
    try! GLFWSession.initialize()

    GLFWWindow.hints.contextVersion = (4, 1)
    GLFWWindow.hints.openGLProfile = .core
    GLFWWindow.hints.openGLCompatibility = .forward
    #if os(macOS)
      GLFWWindow.hints.retinaFramebuffer = false
    #endif
    GLFWWindow.hints.openGLDebugMode = true
  }

  private func setupWindow() {
    window = try! GLFWWindow(
      width: Int(DESIGN_RESOLUTION.width),
      height: Int(DESIGN_RESOLUTION.height),
      title: ""
    )

    #if canImport(AppKit)
      NSWindowSwizzling.run()
      window.nsWindow?.styleMask.insert(.fullSizeContentView)
      window.nsWindow?.titlebarAppearsTransparent = true
      //window.nsWindow?.toolbar = .init()
      window.nsWindow?.hideStandardWindowButtons()
    //window.nsWindow?.darkenStandardWindowButtons()
    #endif

    window.framebufferSizeChangeHandler = { [weak self] _, _, _ in
      self?.advanceMainLoop()
    }

    window.position = .zero
    window.context.makeCurrent()

    // Enable vsync for consistent frame pacing (fixes laggy movement)
    window.context.setSwapInterval(1)

    // We shouldn't need this icon thing for release; it'll be embedded in .app/.exe/etc.
    window.setIcon(GLFW.Image("UI/AppIcon/icon~masked.webp"))
    window.mouse.setCursor(to: .dot)
    //window.mouse.setCursor(to: .regular)
  }

  private func setupEditorWindow() {
    // Create editor window sharing the main window's GL context so GL resources (programs, textures)
    // are visible in both windows. Ensure it starts hidden to avoid flashing at launch.
    let previousVisibleHint = GLFWWindow.hints.visible
    GLFWWindow.hints.visible = false

    editorWindow = try! GLFWWindow(
      width: 400,
      height: Int(DESIGN_RESOLUTION.height),
      title: "",
      sharedContext: window.context
    )

    GLFWWindow.hints.visible = previousVisibleHint

    #if canImport(AppKit)
      object_setClass(editorWindow.nsWindow!, NSPanel.self)
      //if let panel = editorWindow.nsWindow as? NSPanel { panel.isFloatingPanel = true }
      editorWindow.nsWindow?.styleMask.insert(.utilityWindow)
      editorWindow.nsWindow?.styleMask.insert(.fullSizeContentView)
      editorWindow.nsWindow?.titlebarAppearsTransparent = true
      //editorWindow.nsWindow?.isMovableByWindowBackground = true
      editorWindow.nsWindow?.hideStandardWindowButtons()
    //editorWindow.nsWindow?.darkenStandardWindowButtons()
    #endif

    // Position editor window next to main window
    editorWindow.position = GLFW.Point(Int(window.size.width), 0)

    // Don't make editor window context current during setup
    // editorWindow.context.makeCurrent()

    // Handle live resize so our layout uses the correct size
    editorWindow.framebufferSizeChangeHandler = { [weak self] _, w, h in
      guard let self else { return }
      self.editorPanel.updateWindowSize(Size(Float(w), Float(h)))
    }
  }

  private func setupEditorSystem() {
    // Create editor renderer (shared context with main window)
    editorRenderer = {
      if cli.metal {
        do {
          return try MTLRenderer()
        } catch {
          logger.warning("Failed to create Metal renderer for editor, falling back to OpenGL: \(error)")
          return GLRenderer()
        }
      } else {
        return GLRenderer()
      }
    }()

    editorGraphicsContext = GraphicsContext(renderer: editorRenderer, scale: 1, isFlipped: false)
    editorPanel = EditorPanel()

    // Initially hide the editor window
    editorWindow.hide()
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

    // Setup editor system
    setupEditorSystem()
  }

  private func setupLoops() {
    loops = [
      MainLoop(),
      TitleScreenStack(),

      //PauseScreenStack(),

      //DialogDemo(),
      MapView(),
      ItemView(item: .sigp320),
      //PickupView(item: .catStatue),
      StorageView(),
      SaveScreen(),
      LoadScreen(),
      //MainMenu(),
      UIDemo(),
      //DocumentDemo(),
      MovieDemo(),
      ModelViewer(),
      CreditsScreen(),

      InventoryView(),
      GradientDemo(),
      SVGDemo(),
      SlotDemo(),
      SlotGridDemo(),
      LibraryView(),
      CalloutDemo(),
      PromptListDemo(),
      FontsDemo(),
      PathDemo(),
      TextEffectsDemo(),
      //FadeDemo(),
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
    activeLoop = loops[safe: currentLoopIndex] ?? loops.first
    activeLoop.onAttach(window: window)

    // Schedule CLI actions relative to current time
    if cli.screenshot != nil { scheduleScreenshotAt = GLFWSession.currentTime + 1.0 }
    if cli.exit { scheduleExitAt = GLFWSession.currentTime + 2.0 }
  }

  private func setupInputHandlers() {
    window.keyInputHandler = { [weak self] window, key, scancode, state, mods in
      guard let self else { return }
      // If editor is visible and focused, don't forward keys to the main loop to avoid double handling
      if config.editorEnabled && self.editorWindow.isFocused {
        return
      }
      self.activeLoop.onKey(window: window, key: key, scancode: Int32(scancode), state: state, mods: mods)
      if state == .pressed {
        self.activeLoop.onKeyPressed(window: window, key: key, scancode: Int32(scancode), mods: mods)
        handleGlobalDebugCommand(key: key, modifiers: mods)
      }
    }

    // Route text input through activeLoop (consistent with other input handlers)
    window.textInputHandler = { [weak self] window, text in
      guard let self else { return }
      // If editor is visible and focused, don't forward text input to the main loop
      if config.editorEnabled && self.editorWindow.isFocused {
        return
      }
      self.activeLoop.onTextInput(window: window, text: text)
    }

    window.cursorPositionHandler = { [weak self] window, x, y in
      guard let self else { return }
      guard window.isFocused else { return }
      GLScreenEffect.mousePosition = (Float(x), Float(y))
      self.activeLoop.onMouseMove(window: window, x: x, y: y)
    }

    window.scrollInputHandler = { [weak self] window, xOffset, yOffset in
      guard let self else { return }
      self.activeLoop.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
    }

    window.mouseButtonHandler = { [weak self] window, button, state, mods in
      guard let self else { return }
      self.activeLoop.onMouseButton(window: window, button: button, state: state, mods: mods)
      if state == .pressed {
        self.activeLoop.onMouseButtonPressed(window: window, button: button, mods: mods)
      } else if state == .released {
        self.activeLoop.onMouseButtonReleased(window: window, button: button, mods: mods)
      }
    }

    // Add input handlers for editor window
    setupEditorInputHandlers()
  }

  private func setupEditorInputHandlers() {
    editorWindow.keyInputHandler = { [weak self] window, key, scancode, state, mods in
      guard let self else { return }

      // Handle backslash to toggle editor
      if key == .backslash && state == .pressed {
        UISound.select()
        self.toggleEditor()
        return
      }

      // Handle other keys for editor panel (on key press only to avoid double handling on release)
      if config.editorEnabled && state == .pressed {
        _ = self.editorPanel.handleKey(key)
      }
    }

    // Route text input through editor panel (consistent with other input handlers)
    editorWindow.textInputHandler = { [weak self] window, text in
      guard let self else { return }
      if config.editorEnabled {
        // Editor panel can handle text input if needed, but for now we route directly to focused TextField
        // This could be changed to self.editorPanel.onTextInput(...) if we add that method
        if let focusedField = TextField.currentFocusedField {
          _ = focusedField.insertText(text)
        }
      }
    }

    editorWindow.mouseButtonHandler = { [weak self] window, button, state, mods in
      guard let self else { return }

      if config.editorEnabled && button == .left {
        if state == .pressed {
          self.editorPanel.onMouseButtonPressed(window: window, button: button, mods: mods)
        } else if state == .released {
          self.editorPanel.onMouseButtonReleased(window: window, button: button, mods: mods)
        }
      }
    }

    editorWindow.cursorPositionHandler = { [weak self] window, x, y in
      guard let self else { return }

      if config.editorEnabled {
        self.editorPanel.onMouseMove(window: window, x: x, y: y)
      }
    }
  }

  private func handleGlobalDebugCommand(key: Keyboard.Key, modifiers: Keyboard.Modifier) {
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

    case .home:
      UISound.select()
      cycleInputSources()

    case .backslash:
      if modifiers.contains(.shift) {
        UISound.select()
        showStats.toggle()
        if showStats {
          updateWindowTitle()
        } else {
          window.title = ""
        }
      } else {
        UISound.select()
        toggleEditor()
      }

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

    // Update editor panel for new loop
    updateEditorForCurrentLoop()
  }

  private func cycleInputSources() {
    let allSources = InputSource.allCases
    let currentIndex = allSources.firstIndex(of: InputSource.player1) ?? 0
    let nextIndex = (currentIndex + 1) % allSources.count
    InputSource.player1 = allSources[nextIndex]
  }

  private func toggleEditor() {
    config.editorEnabled.toggle()

    #if canImport(AppKit)
      editorWindow.nsWindow?.animationBehavior = .none
    #endif

    if config.editorEnabled {
      editorWindow.show()
      updateEditorForCurrentLoop()
    } else {
      editorWindow.hide()
      // Return focus to main window when hiding editor
      window.focus(force: true)
    }
  }

  private func updateEditorForCurrentLoop() {
    guard config.editorEnabled, let activeLoop else { return }
    editorWindow.title = String(describing: type(of: activeLoop))

    if let editingLoop = activeLoop as? Editing {
      editorPanel.updateForObject(editingLoop)
    } else {
      editorPanel.showNoEditorMessage()
    }
  }

  private func updateWindowTitle() {
    var title = String(
      format: "GL textures: %d | GL buffers: %d | Memory: %.1f MB",
      GLStats.textureCount,
      GLStats.bufferCount,
      Double(reportResidentMemoryBytes()) / (1024.0 * 1024.0)
    )

    #if DEBUG
      title += " | Debug Build"
    #endif

    if let activeLoop {
      window.title = "\(String(describing: type(of: activeLoop))) (\(title))"
    } else {
      window.title = title
    }
  }

  private func renderEditorWindow() {
    // Store current context
    let previousContext = GLFWContext.current

    // Switch to editor window context
    editorWindow.context.makeCurrent()

    // Update viewport size for editor window
    let editorSize = Size(Float(editorWindow.size.width), Float(editorWindow.size.height))
    editorRenderer.beginFrame(windowSize: editorSize)

    // Render editor panel with flipped coordinate system
    GraphicsContext.withContext(editorGraphicsContext) {
      // Set up UI rendering state for editor window
      editorRenderer.withUIContext {
        // Create ambient background effect lazily now that a context is current
        if self.editorAmbientBackground == nil {
          self.editorAmbientBackground = GLScreenEffect("Effects/AmbientBackground")
        }
        // Draw ambient background behind the UI
        self.editorAmbientBackground?.draw { shader in
          shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
          shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
          shader.setFloat("uMottle", value: 0.35)
          shader.setFloat("uGrain", value: 0.08)
          shader.setFloat("uVignette", value: 0.35)
          shader.setFloat("uDust", value: 0.06)
        }
        // Update editor panel with current window size
        editorPanel.updateWindowSize(editorSize)
        editorPanel.draw()
      }
    }

    editorRenderer.endFrame()
    editorWindow.swapBuffers()

    // Restore previous context
    previousContext.makeCurrent()
  }

  private func runMainLoop() {
    lastFrameTime = GLFWSession.currentTime

    while !window.shouldClose {
      if let t = scheduleExitAt, GLFWSession.currentTime >= t {
        break
      }

      advanceMainLoop()

      // Frame pacing: sleep if we're ahead of target frame time
      // This ensures consistent frame timing and smooth movement
      let currentTime = GLFWSession.currentTime
      let frameTime = currentTime - lastFrameTime
      if frameTime < targetFrameTime {
        let sleepTime = targetFrameTime - frameTime
        Thread.sleep(forTimeInterval: sleepTime)
      }
      lastFrameTime = GLFWSession.currentTime
    }
  }

  private func advanceMainLoop() {
    let currentFrame = Float(GLFWSession.currentTime)
    deltaTime = currentFrame - lastFrame
    lastFrame = currentFrame

    activeLoop.update(window: window, deltaTime: deltaTime)

    ScreenFade.shared.update(deltaTime: deltaTime)
    ScreenFadeFBO.shared.update(deltaTime: deltaTime)
    ScreenShake.shared.update(deltaTime: deltaTime)

    let windowSize = Size(Float(window.size.width), Float(window.size.height))

    // When VIEWPORT_SCALING is enabled, UI code uses DESIGN_RESOLUTION coordinates,
    // but the orthographic matrix uses the full window size so coordinates scale up
    let coordinateSpaceSize: Size
    if VIEWPORT_SCALING {
      // UI code uses DESIGN_RESOLUTION coordinates (via Engine.viewportSize)
      coordinateSpaceSize = DESIGN_RESOLUTION
      Self._cachedViewportSize = DESIGN_RESOLUTION
    } else {
      coordinateSpaceSize = windowSize
      Self._cachedViewportSize = windowSize
    }

    // Pass full window size to renderer for actual GL/Metal viewport
    renderer.beginFrame(windowSize: windowSize)
    // Set coordinate space size for orthographic matrix
    // When VIEWPORT_SCALING is enabled, use DESIGN_RESOLUTION so UI coordinates map correctly
    // The GL viewport will automatically scale the output to fill the window
    if let glRenderer = renderer as? GLRenderer {
      glRenderer.setCoordinateSpaceSize(coordinateSpaceSize)
    } else if let metalRenderer = renderer as? MTLRenderer {
      metalRenderer.setCoordinateSpaceSize(coordinateSpaceSize)
    }

    GraphicsContext.withContext(graphicsContext) {
      activeLoop.draw()

      // Draw screen fade in UI context so it always appears on top
      renderer.withUIContext {
        ScreenFade.shared.draw(screenSize: renderer.viewportSize)
        ScreenFadeFBO.shared.draw(screenSize: renderer.viewportSize)
      }
    }

    renderer.endFrame()

    // Render editor window if visible (after main window is done)
    if config.editorEnabled && !editorWindow.shouldClose {
      // Advance editor UI animations with the same deltaTime
      editorPanel.update(deltaTime: deltaTime)
      renderEditorWindow()
    }

    if showStats && GLFWSession.currentTime - lastTitleUpdateTime > 1.0 {
      lastTitleUpdateTime = GLFWSession.currentTime
      updateWindowTitle()
    }

    if let t = scheduleScreenshotAt, GLFWSession.currentTime >= t {
      requestScreenshot = true
      scheduleScreenshotAt = nil
    }

    if requestScreenshot {
      requestScreenshot = false
      saveScreenshot(
        width: Int32(renderer.viewportSize.width),
        height: Int32(renderer.viewportSize.height),
        path: cli.screenshot
      )
    }

    window.swapBuffers()
    GLFWSession.pollInputEvents()
  }
}
