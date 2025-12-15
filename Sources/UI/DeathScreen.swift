import struct GLFW.Keyboard
import struct GLFW.Mouse

// MARK: - DeathScreen

/// The death screen menu with Continue, Load Game, and Quit options
final class DeathScreen: Screen {
  private let listMenu = ListMenu()
  private var skipInputThisFrame: Bool = true  // Skip input on first frame to avoid immediate selection

  override init() {
    super.init()
    setupMenu()
  }

  private func setupMenu() {
    listMenu.style = .boxed
    listMenu.spacing = 52
    listMenu.itemWidth = 280

    let menuItems = [
      ListMenu.MenuItem(id: "continue", label: "Continue") {
        // Continue from last checkpoint
        logger.trace("Death screen: Continue selected")
        if let mainLoop = MainLoop.shared {
          mainLoop.hideDeathScreen()
        }
      },

      ListMenu.MenuItem(id: "load", label: "Load Game") {
        // Navigate to load screen
        logger.trace("Death screen: Load Game selected")
        self.navigate(to: LoadScreen())
      },

      ListMenu.MenuItem(id: "quit", label: "Give Up") {
        // Return to title screen
        logger.trace("Death screen: Give Up selected")
        MainLoop.shared?.showTitleScreen()
      },
    ]

    listMenu.setItems(menuItems)
  }

  override func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
    // Clear skip flag after first update
    skipInputThisFrame = false
    // Handle gamepad navigation
    if let gamepad = Gamepad.allGamepads.first {
      listMenu.handleGamepadInput(gamepad, deltaTime: deltaTime)
    }
  }

  override func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Skip input on first frame to avoid immediate selection from the key that triggered death
    guard !skipInputThisFrame else { return }
    listMenu.handleKeyPressed(key)
  }

  override func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      listMenu.handleMouseClick(at: mousePosition)
    }
  }

  override func onMouseMove(window: Window, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    listMenu.handleMouseMove(at: mousePosition)
  }

  override func draw() {
    let screenWidth = Float(Engine.viewportSize.width)
    let screenHeight = Float(Engine.viewportSize.height)

    // Draw "YOU ARE DEAD" title - high Y = top of screen in OGL
    let titleStyle = TextStyle.deathScreenTitle
    let titleY = screenHeight * 0.72
    String(gameLocalized: LocalizedStringResource("Y O U   A R E   D E A D")).draw(
      at: Point(screenWidth / 2, titleY),
      style: titleStyle,
      anchor: .bottom
    )

    // Menu below title - centered horizontally
    let menuCenterX = screenWidth / 2
    let menuStartY = screenHeight * 0.28

    listMenu.position = Point(menuCenterX, menuStartY)
    listMenu.draw()
  }
}

// MARK: - DeathScreenStack

/// Full death screen that renders a NavigationStack with blood splatter effect
final class DeathScreenStack: RenderLoop {
  private let navigationStack: NavigationStack
  private let promptList: PromptList
  private let bloodEffect = GLScreenEffect("Effects/DeathScreen")

  // Animation timing
  private let overlayFadeInSpeed: Float = 2.5
  private let overlayFadeOutSpeed: Float = 8.0
  private let targetOverlayOpacity: Float = 1.0

  // Overlay fade animation state
  private var overlayOpacity: Float = 0.0
  var isFadingOut: Bool = false

  var isAtRoot: Bool {
    navigationStack.isAtRoot
  }

  var isFadeOutComplete: Bool {
    isFadingOut && overlayOpacity <= 0.001
  }

  init() {
    promptList = PromptList(.menuRoot)
    navigationStack = NavigationStack()
    navigationStack.setInitialScreen(DeathScreen())
  }

  func onAttach(window: Window) {
    overlayOpacity = 0.0
    isFadingOut = false
  }

  func onDetach(window: Window) {
    isFadingOut = true
  }

  func startFadeOut() {
    isFadingOut = true
  }

  func update(deltaTime: Float) {
    navigationStack.update(deltaTime: deltaTime)

    // Animate overlay fade-in or fade-out
    if isFadingOut {
      let overlayDelta = (0.0 - overlayOpacity) * overlayFadeOutSpeed * deltaTime
      overlayOpacity += overlayDelta
      if overlayOpacity < 0.0 {
        overlayOpacity = 0.0
      }
    } else {
      let overlayDelta = (targetOverlayOpacity - overlayOpacity) * overlayFadeInSpeed * deltaTime
      overlayOpacity += overlayDelta
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    navigationStack.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    navigationStack.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    navigationStack.onMouseMove(window: window, x: x, y: y)
  }

  /// Handle gamepad button press for back navigation
  func handleGamepadButton(_ button: Gamepad.Button) -> Bool {
    if button == .b || button == .back {
      if !navigationStack.isAtRoot {
        navigationStack.pop()
        return true
      }
    }
    return false
  }

  func draw() {
    let screenSize = Engine.viewportSize

    // Draw the blood splatter effect as background
    if overlayOpacity > 0.0 {
      bloodEffect.draw { program in
        program.setFloat("amount", value: overlayOpacity)
      }
    }

    // Calculate menu opacity based on overlay opacity
    let menuOpacity = min(1.0, overlayOpacity / max(0.001, targetOverlayOpacity))

    // Only draw menu content if it's visible
    if menuOpacity > 0.01 {
      // Render navigation stack to framebuffer with alpha
      let menuFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)

      Engine.shared.renderer.beginFramebuffer(menuFBO)
      navigationStack.draw()
      Engine.shared.renderer.endFramebuffer()

      // Draw framebuffer with alpha
      Engine.shared.renderer.drawFramebuffer(
        menuFBO,
        in: Rect(origin: .zero, size: screenSize),
        transform: nil,
        alpha: menuOpacity
      )

      Engine.shared.renderer.destroyFramebuffer(menuFBO)

      if !navigationStack.usesFullScreenContent {
        promptList.group = navigationStack.isAtRoot ? .menuRoot : .menu
        promptList.showCalloutBackground = false
        promptList.draw(opacity: menuOpacity)
      }
    }
  }
}
