@Editor final class MainMenu: RenderLoop {
  private let objectiveCallout = Callout("Make your way to Kastellet", icon: .chevron)

  @Editable(range: 100...400) var tabsRightMargin: Float = 380
  @Editable var health: Float = 1.0 { didSet { inventoryView.healthDisplay.health = health } }

  // Tab views
  private let mapView = MapView()
  private let inventoryView = InventoryView()
  private let libraryView = LibraryView()
  // Tab management
  private let tabs = MainMenuTabs()

  // Current active view
  private var activeView: RenderLoop {
    switch tabs.activeTab {
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

    // Set up tab callbacks
    tabs.canSwitchTabs = { [weak self] in
      guard let self = self else { return false }
      return !(self.tabs.activeTab == .library && self.libraryView.showingDocument)
        && !(self.tabs.activeTab == .inventory && self.inventoryView.showingItem)
    }
  }

  func setActiveTab(_ tab: MainMenuTabs.Tab, animated: Bool = true) {
    tabs.setActiveTab(tab, animated: animated)
  }

  /// Check if there's a nested view open (item, document, or popup menu)
  var hasNestedViewOpen: Bool {
    // Check for popup menu in inventory slot grid
    if tabs.activeTab == .inventory && inventoryView.isSlotMenuVisible {
      return true
    }
    // Check for item view in inventory
    if tabs.activeTab == .inventory && inventoryView.showingItem {
      return true
    }
    // Check for document view in library
    if tabs.activeTab == .library && libraryView.showingDocument {
      return true
    }
    return false
  }

  func update(window: Window, deltaTime: Float) {
    tabs.rightMargin = tabsRightMargin
    tabs.update(deltaTime: deltaTime)
    activeView.update(window: window, deltaTime: deltaTime)
    objectiveCallout.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Handle tab switching first
    if tabs.handleKeyPress(key) {
      return
    }

    switch key {
    case .escape:
      // Exit main menu - could be handled by parent
      break
    default:
      break
    }

    // Forward input to active view
    activeView.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    activeView.onMouseMove(window: window, x: x, y: y)
  }

  func onMouseButton(window: Window, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    activeView.onMouseButton(window: window, button: button, state: state, mods: mods)
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    // Handle tab clicking first
    if button == .left
      && tabs.handleMouseClick(at: Point(Float(window.mouse.position.x), Float(window.mouse.position.y)))
    {
      return
    }

    activeView.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    activeView.onMouseButtonReleased(window: window, button: button, mods: mods)
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    activeView.onScroll(window: window, xOffset: xOffset, yOffset: yOffset)
  }

  func draw() {
    // Draw the active view
    activeView.draw()

    // Only draw tab icons if we're not showing a document in the library or item in inventory
    if !(tabs.activeTab == .library && libraryView.showingDocument)
      && !(tabs.activeTab == .inventory && inventoryView.showingItem)
    {
      tabs.draw()
      objectiveCallout.draw()
    }
  }

}

// MARK: - MainMenuTabs

@MainActor
final class MainMenuTabs {
  // Tab management
  enum Tab: Int, CaseIterable {
    case map
    case inventory
    case library
  }

  var rightMargin: Float = 0

  private var currentTab: Tab = .inventory

  // Mouse tracking
  private var mousePosition: Point = Point.zero

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

  var onTabChanged: ((Tab) -> Void)?
  var canSwitchTabs: () -> Bool = { true }

  var activeTab: Tab {
    return currentTab
  }

  func setActiveTab(_ tab: Tab, animated: Bool = true) {
    currentTab = tab
    onTabChanged?(currentTab)

    if !animated {
      // Immediately set animation progress and scales for all tabs
      for tabItem in Tab.allCases {
        let isActive = tabItem == currentTab
        let targetProgress: Float = isActive ? 1.0 : 0.0
        animationProgress[tabItem] = targetProgress

        // Calculate final scale immediately
        let easedProgress = easing.apply(targetProgress)
        let scale = lerp(inactiveIconScale, activeIconScale, easedProgress)
        iconScales[tabItem] = scale
      }
    }
  }

  func update(deltaTime: Float) {
    updateIconScales(deltaTime: deltaTime)
  }

  func updateMousePosition(_ position: Point) {
    mousePosition = position
  }

  func handleKeyPress(_ key: Keyboard.Key) -> Bool {
    switch key {
    case .q:
      if canSwitchTabs() {
        cycleTab(-1)
        return true
      }
      return false
    case .e:
      if canSwitchTabs() {
        cycleTab(1)
        return true
      }
      return false
    default:
      return false
    }
  }

  func handleMouseClick(at position: Point) -> Bool {
    if let clickedTab = getTabAtMousePosition(at: position) {
      if canSwitchTabs() {
        currentTab = clickedTab
        onTabChanged?(currentTab)
        UISound.select()
        return true
      }
    }
    return false
  }

  func draw() {
    drawTabIcons()
  }

  // MARK: - Private Methods

  private func getTabAtMousePosition(at position: Point) -> Tab? {
    if !canSwitchTabs() {
      return nil
    }
    let iconSpacing: Float = 72
    let totalWidth = Float(Tab.allCases.count - 1) * iconSpacing
    let isCentered = Config.current.centeredLayout
    let startX: Float = {
      if isCentered {
        return (Float(Engine.viewportSize.width) - totalWidth) * 0.5
      } else {
        // Right-align the tabs; include extra margin to align with grid
        return Float(Engine.viewportSize.width) - totalWidth - rightMargin
      }
    }()
    let iconY: Float = 212

    for (index, tab) in Tab.allCases.enumerated() {
      let iconX = startX + Float(index) * iconSpacing

      // Use animated scale for hit detection
      let scale = iconScales[tab] ?? inactiveIconScale
      let scaledSize = baseIconSize * scale

      // Create hit area rectangle
      let hitRect = Rect(
        x: iconX - scaledSize * 0.5,
        y: iconY - scaledSize * 0.5,
        width: scaledSize,
        height: scaledSize
      )

      // Check if mouse position is within this tab's hit area
      if hitRect.contains(position) {
        return tab
      }
    }

    return nil
  }

  private func cycleTab(_ direction: Int) {
    UISound.select()
    let tabCount = Tab.allCases.count
    let newIndex = (currentTab.rawValue + direction + tabCount) % tabCount
    currentTab = Tab(rawValue: newIndex)!
    onTabChanged?(currentTab)
  }

  private func updateIconScales(deltaTime: Float) {
    for tab in Tab.allCases {
      let isActive = tab == currentTab
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
    let isCentered = Config.current.centeredLayout
    let startX: Float = {
      if isCentered {
        return (Float(Engine.viewportSize.width) - totalWidth) * 0.5
      } else {
        // Shift a bit further left than the grid's margin to center over grid
        return Float(Engine.viewportSize.width) - totalWidth - rightMargin
      }
    }()
    let iconY: Float = Float(Engine.viewportSize.height) - 212

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
