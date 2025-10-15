// import GL
import GLFW
import GLMath

final class MainMenu: RenderLoop {
  // Tab views
  private let mapView = MapView()
  private let inventoryView = InventoryView()
  private let libraryView = LibraryView()

  // Tab management
  private enum Tab: Int, CaseIterable {
    case map
    case inventory
    case library
  }

  private var currentTab: Tab = .inventory

  // Tab icons
  private let tabIcons: [Tab: Image] = [
    .map: Image("UI/Icons/phosphor-icons/map-pin-fill.svg", size: 48),
    .inventory: Image("UI/Icons/phosphor-icons/bag-simple-fill.svg", size: 48),
    .library: Image("UI/Icons/phosphor-icons/book-fill.svg", size: 48),
  ]

  // Navigation prompts
  private let prevPrompt = Prompt([["keyboard_q"], ["xbox_lb"], ["playstation_trigger_l1"]])
  private let nextPrompt = Prompt([["keyboard_e"], ["xbox_rb"], ["playstation_trigger_r1"]])

  // Icon scaling
  private let baseIconSize: Float = 48.0
  private let activeIconScale: Float = 1.0
  private let inactiveIconScale: Float = 0.8

  // Animation state
  private var iconScales: [Tab: Float] = [.map: 0.8, .inventory: 1.0, .library: 0.8]
  private var animationProgress: [Tab: Float] = [.map: 0.0, .inventory: 1.0, .library: 0.0]
  private let animationDuration: Float = 0.25
  private let easing: Easing = .easeInOutQuad

  // Current active view
  private var activeView: RenderLoop {
    switch currentTab {
    case .inventory: return inventoryView
    case .map: return mapView
    case .library: return libraryView
    }
  }

  init() {
    // Initialize all views
    inventoryView.onAttach(window: Engine.shared.window)
    mapView.onAttach(window: Engine.shared.window)
    libraryView.onAttach(window: Engine.shared.window)
  }

  func update(deltaTime: Float) {
    activeView.update(deltaTime: deltaTime)

    // Animate icon scales
    updateIconScales(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Don't allow tab switching when showing a document or item
    if !(currentTab == .library && libraryView.showingDocument)
      && !(currentTab == .inventory && inventoryView.showingItem)
    {
      // Handle tab switching first
      switch key {
      case .q:
        cycleTab(-1)
        return
      case .e:
        cycleTab(1)
        return
      case .escape:
        // Exit main menu - could be handled by parent
        break
      default:
        break
      }
    }

    // Forward input to active view
    activeView.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    activeView.onMouseMove(window: window, x: x, y: y)
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    activeView.onMouseButton(window: window, button: button, state: state, mods: mods)
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    activeView.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    activeView.onMouseButtonReleased(window: window, button: button, mods: mods)
  }

  func onScroll(window: GLFWWindow, xOffset: Double, yOffset: Double) {
    activeView.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
  }

  func draw() {
    // Draw the active view
    activeView.draw()

    // Only draw tab icons if we're not showing a document in the library or item in inventory
    if !(currentTab == .library && libraryView.showingDocument)
      && !(currentTab == .inventory && inventoryView.showingItem)
    {
      drawTabIcons()
    }
  }

  // MARK: - Private Methods

  private func cycleTab(_ direction: Int) {
    let tabCount = Tab.allCases.count
    let newIndex = (currentTab.rawValue + direction + tabCount) % tabCount
    currentTab = Tab(rawValue: newIndex)!
    UISound.select()
  }

  private func updateIconScales(deltaTime: Float) {
    for tab in Tab.allCases {
      let isActive = tab == currentTab
      let targetProgress: Float = isActive ? 1.0 : 0.0
      let currentProgress = animationProgress[tab] ?? (isActive ? 1.0 : 0.0)

      // Update animation progress
      let progressDelta = deltaTime / animationDuration
      let newProgress: Float
      if isActive {
        newProgress = min(1.0, currentProgress + progressDelta)
      } else {
        newProgress = max(0.0, currentProgress - progressDelta)
      }
      animationProgress[tab] = newProgress

      // Apply easing and calculate final scale
      let easedProgress = easing.apply(newProgress)
      let scale = lerp(inactiveIconScale, activeIconScale, easedProgress)
      iconScales[tab] = scale
    }
  }

  private func drawTabIcons() {
    let iconSpacing: Float = 72
    let totalWidth = Float(Tab.allCases.count - 1) * iconSpacing
    let startX = (Float(Engine.viewportSize.width) - totalWidth) * 0.5
    let iconY: Float = Float(Engine.viewportSize.height) - 80

    // Draw prompts further down
    let promptY = iconY
    let promptSpacing: Float = 64

    // Previous prompt on the left
    let prevPromptX = startX - promptSpacing
    prevPrompt.targetIconHeight = 32
    prevPrompt.draw(at: Point(prevPromptX, promptY), anchor: .center)

    // Next prompt on the right
    let nextPromptX = startX + totalWidth + promptSpacing
    nextPrompt.targetIconHeight = 32
    nextPrompt.draw(at: Point(nextPromptX, promptY), anchor: .center)

    // Draw tab icons
    for (index, tab) in Tab.allCases.enumerated() {
      let iconX = startX + Float(index) * iconSpacing
      let isActive = tab == currentTab

      guard let icon = tabIcons[tab] else { continue }

      // Use animated scale
      let scale = iconScales[tab] ?? inactiveIconScale
      let scaledSize = baseIconSize * scale

      // Anchor the icon at the center
      let iconRect = Rect(
        x: iconX - scaledSize * 0.5,
        y: iconY - scaledSize * 0.5,
        width: scaledSize,
        height: scaledSize
      )

      // Draw icon with appropriate opacity
      let opacity: Float = isActive ? 0.8 : 0.2
      icon.draw(in: iconRect, tint: Color.white.withAlphaComponent(opacity))
    }
  }
}
