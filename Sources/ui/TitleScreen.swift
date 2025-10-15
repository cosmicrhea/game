import GLFW

/// Menu-only component for the title screen
final class TitleScreen: Screen {
  private let listMenu = ListMenu()

  @MainActor
  override init() {
    super.init()
    setupMenu()
  }

  private func setupMenu() {
    let menuItems = [
      ListMenu.MenuItem(id: "new_game", label: "New Game") {
        print("Starting new game...")
      },

      ListMenu.MenuItem(id: "continue", label: "Continue", isEnabled: false) {
        print("Loading saved game...")
      },

      ListMenu.MenuItem(id: "options", label: "Options") {
        // Navigate to options screen
        self.navigate(to: OptionsScreen())
      },

      ListMenu.MenuItem(id: "give_up", label: "Give Up") {
        Task { @MainActor in
          #if os(macOS)
            Engine.shared.window.nsWindow?.animationBehavior = .utilityWindow
            Engine.shared.window.nsWindow?.close()
            await Task.sleep(0.5)
          #endif

          Engine.shared.window.close()
        }
      },
    ]

    listMenu.setItems(menuItems)
  }

  override func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
  }

  override func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    listMenu.handleKeyPressed(key)
  }

  override func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      listMenu.handleMouseClick(at: mousePosition)
    }
  }

  override func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    listMenu.handleMouseMove(at: mousePosition)
  }

  override func draw() {
    // Draw the menu using ListMenu
    listMenu.draw()
  }
}

/// Full title screen that renders a NavigationStack
final class TitleScreenStack: RenderLoop {
  private let navigationStack: NavigationStack
  private let backgroundImage = Image("UI/title_screen.png")
  private let promptList: PromptList
  private let vignetteEffect = GLScreenEffect("Effects/TitleScreenVignette")
  private var animatedVignetteStrength: Float = 0.0

  init() {
    // Create prompt list for title screen
    promptList = PromptList(.menuRoot)

    // Create navigation stack (no background, no prompts - TitleScreen handles those)
    navigationStack = NavigationStack()

    // Set the initial menu
    let titleMenu = TitleScreen()
    navigationStack.setInitialScreen(titleMenu)
  }

  func update(deltaTime: Float) {
    navigationStack.update(deltaTime: deltaTime)

    // Animate vignette strength based on navigation state
    let targetVignetteStrength: Float = navigationStack.isAtRoot ? 0.0 : 0.6
    let vignetteSpeed: Float = 3.0  // Animation speed

    // Smooth interpolation towards target
    let vignetteDelta = (targetVignetteStrength - animatedVignetteStrength) * vignetteSpeed * deltaTime
    animatedVignetteStrength += vignetteDelta
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    navigationStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    navigationStack.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    navigationStack.onMouseMove(window: window, x: x, y: y)
  }

  func draw() {
    // Set clear color to black
    GraphicsContext.current?.renderer.setClearColor(.black)

    let screenWidth = Float(Engine.viewportSize.width)
    let screenHeight = Float(Engine.viewportSize.height)

    // Draw background image
    let backgroundRect = Rect(x: 0, y: 0, width: screenWidth, height: screenHeight)
    backgroundImage.draw(in: backgroundRect)

    // Draw vignette effect - smoothly animated
    if animatedVignetteStrength > 0.0 {
      // Apply vignette effect using the shader
      vignetteEffect.draw(["amount": animatedVignetteStrength])
    }

    // Draw the navigation stack (which includes the menu)
    navigationStack.draw()

    // Draw prompts (no animation) - set group based on navigation state
    promptList.group = navigationStack.isAtRoot ? .menuRoot : .menu
    promptList.showCalloutBackground = false
    promptList.draw()

    // Draw version text in bottom left corner
    let versionText = "v\(Engine.versionString)"
    let versionX: Float = 56
    let versionY: Float = 20
    versionText.draw(at: Point(versionX, versionY), style: .version, alignment: .bottomLeft)
  }
}
