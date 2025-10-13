import GLFW

/// Simple options screen that's just a ListMenu
final class OptionsScreen: RenderLoop {
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
    // Handle ESC key to go back
    if key == .escape {
      UISound.select()
      navigationStack.pop()
      return
    }

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
    // Just draw the menu - no background, no extra stuff
    listMenu.draw()
  }
}
