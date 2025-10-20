import GLFW

/// Simple options screen that's just a ListMenu
final class OptionsScreen: Screen {
  private let listMenu = ListMenu()
  private let audioPanel = AudioOptionsPanel()
  private var showingAudio = false

  @MainActor
  override init() {
    super.init()
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
        UISound.select()
        self.showingAudio = true
      },
      ListMenu.MenuItem(id: "language", label: "Language") {
        print("Opening language settings...")
        // TODO: Navigate to language submenu
      },
      ListMenu.MenuItem(id: "graphics", label: "Graphics") {
        print("Opening graphics settings...")
        // TODO: Navigate to graphics submenu
      },
    ]

    listMenu.setItems(menuItems)
  }

  override func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
  }

  override func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if showingAudio {
      if key == .escape {
        UISound.select()
        showingAudio = false
        return
      }
      if audioPanel.handleKey(key) { return }
    }

    switch key {
    case .escape:
      // ESC key to go back
      UISound.select()
      back()

    default:
      listMenu.handleKeyPressed(key)
    }
  }

  override func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    switch button {
    case .left:
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      if showingAudio {
        audioPanel.onMouseButtonPressed(window: window, button: button, mods: mods)
      } else {
        listMenu.handleMouseClick(at: mousePosition)
      }

    case .right:
      // Right click to go back
      if showingAudio {
        UISound.select()
        showingAudio = false
      } else {
        UISound.select()
        back()
      }

    default:
      break
    }
  }

  override func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    if showingAudio {
      audioPanel.onMouseMove(window: window, x: x, y: y)
    } else {
      listMenu.handleMouseMove(at: mousePosition)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if showingAudio {
      if state == .released {
        audioPanel.onMouseButtonReleased(window: window, button: button, mods: mods)
      }
    }
  }

  override func draw() {
    // Left column menu
    listMenu.draw()

    // Right panel when showing audio
    if showingAudio {
      audioPanel.draw()
    }
  }
}
