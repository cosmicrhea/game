import GLFW

/// Menu-only component for the title screen
final class TitleScreenMenu: RenderLoop {
  private let listMenu = ListMenu()
  private let navigationStack: NavigationStack

  init(navigationStack: NavigationStack) {
    self.navigationStack = navigationStack
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
        let optionsScreen = OptionsScreen(navigationStack: self.navigationStack)
        self.navigationStack.push(optionsScreen, direction: .forward)
      },
      ListMenu.MenuItem(id: "give_up", label: "Give Up") {
        Task { @MainActor in
          #if os(macOS)
            Engine.shared.window.nsWindow?.animationBehavior = .utilityWindow
            Engine.shared.window.nsWindow?.close()
            try? await Task.sleep(nanoseconds: 500_000_000)
          #endif
          Engine.shared.window.close()
        }
      },
    ]

    listMenu.setItems(menuItems)
  }

  func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    listMenu.handleKeyPressed(key)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      let mousePosition = Point(Float(window.mouse.position.x), Float(HEIGHT) - Float(window.mouse.position.y))
      listMenu.handleMouseClick(at: mousePosition)
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(HEIGHT) - Float(y))
    listMenu.handleMouseMove(at: mousePosition)
  }

  func draw() {
    // Draw the menu using ListMenu
    listMenu.draw()
  }
}

/// Full title screen that renders a NavigationStack
final class TitleScreen: RenderLoop {
  private let navigationStack: NavigationStack
  private let backgroundImage = Image("UI/title_screen.png")
  private let promptList: PromptList

  init() {
    // Create prompt list for title screen
    promptList = PromptList(.menuRoot)

    // Create navigation stack (no background, no prompts - TitleScreen handles those)
    navigationStack = NavigationStack()

    // Set the initial menu
    let titleMenu = TitleScreenMenu(navigationStack: navigationStack)
    navigationStack.setInitialScreen(titleMenu)
  }

  func update(deltaTime: Float) {
    navigationStack.update(deltaTime: deltaTime)
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

    let screenWidth = Float(WIDTH)
    let screenHeight = Float(HEIGHT)

    // Draw background image
    let backgroundRect = Rect(x: 0, y: 0, width: screenWidth, height: screenHeight)
    backgroundImage.draw(in: backgroundRect)

    // Draw the navigation stack (which includes the menu)
    navigationStack.draw()

    // Draw prompts (no animation)
    promptList.showCalloutBackground = false
    promptList.draw()

    // Draw version text in bottom left corner
    let versionText = "v\(Engine.versionString)"
    let versionX: Float = 56
    let versionY: Float = 20
    versionText.draw(at: Point(versionX, versionY), style: .version, anchor: .bottomLeft)
  }
}
