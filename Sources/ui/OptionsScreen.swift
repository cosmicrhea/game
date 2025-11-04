final class OptionsScreen: Screen {
  enum Panel {
    case controls
    case camera
    case display
    case audio
    case language
    case graphics
  }

  private let listMenu = ListMenu()
  private let controlsPanel = ControlsOptionsPanel()
  private let cameraPanel = CameraOptionsPanel()
  private let displayPanel = DisplayOptionsPanel()
  private let audioPanel = AudioOptionsPanel()
  private let languagePanel = LanguageOptionsPanel()
  private let graphicsPanel = GraphicsOptionsPanel()
  private var currentPanel: Panel? = nil

  private var activePanel: OptionsPanel? {
    guard let currentPanel else { return nil }
    switch currentPanel {
    case .controls: return controlsPanel
    case .camera: return cameraPanel
    case .display: return displayPanel
    case .audio: return audioPanel
    case .language: return languagePanel
    case .graphics: return graphicsPanel
    }
  }

  override init() {
    super.init()

    let menuItems = [
      ListMenu.MenuItem(id: "controls", label: "Controls") {
        UISound.select()
        self.currentPanel = .controls
      },
      ListMenu.MenuItem(id: "camera", label: "Camera") {
        UISound.select()
        self.currentPanel = .camera
      },
      ListMenu.MenuItem(id: "display", label: "Display") {
        UISound.select()
        self.currentPanel = .display
      },
      ListMenu.MenuItem(id: "audio", label: "Audio") {
        UISound.select()
        self.currentPanel = .audio
      },
      ListMenu.MenuItem(id: "language", label: "Language") {
        UISound.select()
        self.currentPanel = .language
      },
      ListMenu.MenuItem(id: "graphics", label: "Graphics") {
        UISound.select()
        self.currentPanel = .graphics
      },
    ]

    listMenu.setItems(menuItems)
  }

  override func update(deltaTime: Float) {
    listMenu.update(deltaTime: deltaTime)
  }

  override func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if let activePanel {
      if key == .escape {
        UISound.select()
        currentPanel = nil
        return
      }
      if activePanel.handleKey(key) { return }
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

  override func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    switch button {
    case .left:
      let mousePosition = Point(
        Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
      if let activePanel {
        activePanel.onMouseButtonPressed(window: window, button: button, mods: mods)
      } else {
        listMenu.handleMouseClick(at: mousePosition)
      }

    case .right:
      // Right click to go back
      if currentPanel != nil {
        UISound.select()
        currentPanel = nil
      } else {
        UISound.select()
        back()
      }

    default:
      break
    }
  }

  override func onMouseMove(window: Window, x: Double, y: Double) {
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    if let activePanel {
      activePanel.onMouseMove(window: window, x: x, y: y)
    } else {
      listMenu.handleMouseMove(at: mousePosition)
    }
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if let activePanel {
      if state == .released {
        activePanel.onMouseButtonReleased(window: window, button: button, mods: mods)
      }
    }
  }

  override func draw() {
    // Left column menu
    listMenu.draw()

    // Right panel when showing a panel
    if let activePanel {
      activePanel.draw()
    }
  }
}
