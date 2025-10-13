import GLFW

/// Menu-only component for the options screen
final class OptionsScreenMenu: RenderLoop {
  private let listMenu = ListMenu()
  private let navigationStack: NavigationStack

  init(navigationStack: NavigationStack) {
    self.navigationStack = navigationStack
    setupMenu()
  }

  private func setupMenu() {
    let menuItems = [
      ListMenu.MenuItem(id: "controls", label: "Controls") {
        print("Opening controls settings...")
        // TODO: Navigate to controls submenu
      },
      ListMenu.MenuItem(id: "camera", label: "Camera") {
        print("Opening camera settings...")
        // TODO: Navigate to camera submenu
      },
      ListMenu.MenuItem(id: "display", label: "Display") {
        print("Opening display settings...")
        // TODO: Navigate to display submenu
      },
      ListMenu.MenuItem(id: "audio", label: "Audio") {
        print("Opening audio settings...")
        // TODO: Navigate to audio submenu
      },
      ListMenu.MenuItem(id: "language", label: "Language") {
        print("Opening language settings...")
        // TODO: Navigate to language submenu
      },
      ListMenu.MenuItem(id: "graphics", label: "Graphics") {
        print("Opening graphics settings...")
        // TODO: Navigate to graphics submenu
      },
      ListMenu.MenuItem(id: "back", label: "Back") {
        // Go back using navigation stack
        self.navigationStack.pop()
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

/// Full options screen that renders a NavigationStack
final class OptionsScreen: RenderLoop {
  private let navigationStack: NavigationStack
  private let backgroundImage = Image("UI/title_screen.png")  // Use same background for now

  init() {
    // Create navigation stack with options screen background
    navigationStack = NavigationStack(backgroundImage: backgroundImage, promptGroup: .menuRoot)

    // Set the initial menu
    let optionsMenu = OptionsScreenMenu(navigationStack: navigationStack)
    navigationStack.setInitialScreen(optionsMenu)
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
  }
}
