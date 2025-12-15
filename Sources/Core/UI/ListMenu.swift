/// A reusable menu component that can be used in different screens
@MainActor
public class ListMenu {
  // MARK: - Style
  public enum Style {
    /// Default style: left-aligned, red selected text, indentation animation
    case `default`
    /// Boxed style: centered, white/gray text, focus ring around selected item
    case boxed
  }

  // MARK: - MenuItem
  public struct MenuItem {
    public let id: String
    public let label: String
    public let labelKey: String
    public let isEnabled: Bool
    public let action: () -> Void

    @_disfavoredOverload
    public init(id: String, label: String, isEnabled: Bool = true, action: @escaping () -> Void) {
      self.id = id
      self.label = label
      self.labelKey = ""
      self.isEnabled = isEnabled
      self.action = action
    }

    public init(id: String, label: LocalizedStringResource, isEnabled: Bool = true, action: @escaping () -> Void) {
      self.id = id
      self.label = ""
      self.labelKey = label.key
      self.isEnabled = isEnabled
      self.action = action
    }
  }

  // MARK: - Properties
  public private(set) var selectedIndex: Int = 0
  public private(set) var menuItems: [MenuItem] = []
  public var style: Style = .default

  // MARK: - Positioning
  public var position: Point = Point(96, 0)  // Default left-aligned position
  public var spacing: Float = 60
  public var indentAmount: Float = 20
  public var itemWidth: Float = 280  // Width for boxed style hit detection and focus ring

  // MARK: - Animation
  public var animationDuration: Float = 0.3
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var previousSelectedIndex: Int = 0
  private let menuAnimationEasing: Easing = .easeOutCubic

  // MARK: - Focus Ring (for boxed style)
  private lazy var focusRing: FocusRing = {
    let ring = FocusRing(isInterior: true)
    ring.cornerRadius = 6
    ring.ringThickness = 3
    ring.glowThickness = 6
    ring.baseAlpha = 0.6
    ring.glowAlpha = 0.3
    ring.pulseStrength = 0.12
    ring.showBackground = true
    ring.backgroundColor = Color(0.2, 0.2, 0.22, 0.7)
    return ring
  }()

  // MARK: - Callbacks
  public var onSelectionChanged: ((Int) -> Void)?
  public var onItemSelected: ((MenuItem) -> Void)?

  public init() {}

  // MARK: - Public Methods

  /// Set the menu items
  public func setItems(_ items: [MenuItem]) {
    self.menuItems = items
    self.selectedIndex = 0
  }

  /// Update animation (call this every frame)
  public func update(deltaTime: Float) {
    if isAnimating {
      animationTime += deltaTime
      if animationTime >= animationDuration {
        animationTime = animationDuration
        isAnimating = false
      }
    }
  }

  /// Handle keyboard input
  @discardableResult
  public func handleKeyPressed(_ key: Keyboard.Key) -> Bool {
    switch key {
    case .up, .w:
      cycleSelection(direction: -1)
      return true
    case .down, .s:
      cycleSelection(direction: +1)
      return true
    case .f, .space, .enter, .numpadEnter:
      // Only process on actual key presses, not repeats
      guard !Engine.isKeyRepeat else { return true }
      handleMenuSelection()
      return true
    default:
      return false
    }
  }

  // MARK: - Gamepad Navigation State
  private var navigationCooldown = GamepadNavigationCooldown(duration: 0.2)
  private var navigationState = GamepadNavigationState()

  /// Handle gamepad input for navigation
  @discardableResult
  public func handleGamepadInput(_ gamepad: Gamepad, deltaTime: Float) -> Bool {
    // Update cooldown
    let cooldownReady = navigationCooldown.update(deltaTime: deltaTime)

    // Check for navigation changes
    let navChanges = navigationState.update(from: gamepad, deadzone: 0.3, trackButtons: true)

    // Handle navigation (only if cooldown expired)
    if cooldownReady {
      if navChanges.up {
        cycleSelection(direction: -1)
        navigationCooldown.reset()
      } else if navChanges.down {
        cycleSelection(direction: +1)
        navigationCooldown.reset()
      }
    }

    // Handle selection (A button press, not hold)
    if navChanges.buttonA {
      // Update input source when gamepad is used
      InputSource.updateFromGamepad(gamepad)
      handleMenuSelection()
    }

    return navChanges.hasAnyDirection || navChanges.buttonA
  }

  /// Handle mouse click
  @discardableResult
  public func handleMouseClick(at mousePosition: Point) -> Bool {
    let itemIndex = getItemIndexAt(mousePosition)
    if let index = itemIndex, index != selectedIndex {
      startMenuAnimation(from: selectedIndex, to: index)
      selectedIndex = index
      onSelectionChanged?(selectedIndex)
      UISound.navigate()
      return true
    } else if itemIndex != nil {
      handleMenuSelection()
      return true
    }
    return false
  }

  /// Handle mouse move for hover effects
  @discardableResult
  public func handleMouseMove(at mousePosition: Point) -> Bool {
    let itemIndex = getItemIndexAt(mousePosition)
    if let index = itemIndex, index != selectedIndex {
      startMenuAnimation(from: selectedIndex, to: index)
      selectedIndex = index
      onSelectionChanged?(selectedIndex)
      UISound.navigate()
      return true
    }
    return false
  }

  /// Draw the menu
  public func draw() {
    guard !menuItems.isEmpty else { return }

    // If position.y is 0, use auto-calculated Y (default behavior for existing menus)
    // Otherwise, use the custom position.y
    let menuStartY: Float
    if position.y == 0 {
      let screenHeight = Float(Engine.viewportSize.height)
      menuStartY = screenHeight - 64 - (Float(menuItems.count) * spacing)
    } else {
      menuStartY = position.y
    }

    for (index, item) in menuItems.enumerated() {
      let isSelected = selectedIndex == index
      let isDisabled = !item.isEnabled

      let baseY = menuStartY + Float(menuItems.count - 1 - index) * spacing

      let effectiveLabel =
        if !item.labelKey.isEmpty {
          Bundle.game.localizedString(forKey: item.labelKey, value: nil, table: "Localizable", locale: .game)
        } else {
          item.label
        }

      switch style {
      case .default:
        // Default style: left-aligned with indentation and red selection
        let finalStyle = TextStyle.menuItem(selected: isSelected, disabled: isDisabled)
        let baseX = position.x

        var finalX = baseX

        // Apply indentation animation for selected item
        if isSelected {
          let animationProgress = isAnimating ? (animationTime / animationDuration) : 1.0
          let easedProgress = menuAnimationEasing.apply(animationProgress)
          finalX = baseX + (indentAmount * easedProgress)
        } else if isAnimating && index == previousSelectedIndex {
          // Animate the previously selected item back to normal position
          let animationProgress = (animationTime / animationDuration)
          let easedProgress = menuAnimationEasing.apply(animationProgress)
          finalX = baseX + (indentAmount * (1.0 - easedProgress))
        }

        effectiveLabel.draw(at: Point(finalX, baseY), style: finalStyle)

      case .boxed:
        // Boxed style: centered with focus ring and white/gray text
        let finalStyle = TextStyle.menuItemBoxed(selected: isSelected, disabled: isDisabled)
        let centerX = position.x

        // Draw focus ring first
        if isSelected {
          let itemRect = Rect(
            x: centerX - itemWidth / 2,
            y: baseY - 6,
            width: itemWidth,
            height: 44
          )
          focusRing.draw(around: itemRect, intensity: 1.0, padding: 4)
        }

        // Draw text on top
        effectiveLabel.draw(at: Point(centerX, baseY), style: finalStyle, anchor: .bottom)
      }
    }
  }

  // MARK: - Private Methods

  private func cycleSelection(direction: Int) {
    let newIndex = (selectedIndex + direction + menuItems.count) % menuItems.count
    if newIndex != selectedIndex {
      startMenuAnimation(from: selectedIndex, to: newIndex)
      selectedIndex = newIndex
      onSelectionChanged?(selectedIndex)
      UISound.navigate()
    }
  }

  private func startMenuAnimation(from: Int, to: Int) {
    previousSelectedIndex = from
    animationTime = 0.0
    isAnimating = true
  }

  private func handleMenuSelection() {
    let selectedItem = menuItems[selectedIndex]
    //print("Selected: \(selectedItem.label)")

    if selectedItem.isEnabled {
      UISound.select()
      onItemSelected?(selectedItem)
      selectedItem.action()
    } else {
      UISound.error()
    }
  }

  private func getItemIndexAt(_ mousePosition: Point) -> Int? {
    // Use same Y logic as draw()
    let menuStartY: Float
    if position.y == 0 {
      let screenHeight = Float(Engine.viewportSize.height)
      menuStartY = screenHeight - 64 - (Float(menuItems.count) * spacing)
    } else {
      menuStartY = position.y
    }
    let menuItemHeight: Float = 40

    for (index, _) in menuItems.enumerated() {
      let itemY = menuStartY + Float(menuItems.count - 2 - index) * spacing

      let itemBounds: Rect
      switch style {
      case .default:
        itemBounds = Rect(
          x: position.x,
          y: itemY,
          width: 300,
          height: menuItemHeight
        )
      case .boxed:
        // Centered hit detection
        itemBounds = Rect(
          x: position.x - itemWidth / 2,
          y: itemY,
          width: itemWidth,
          height: menuItemHeight
        )
      }

      if itemBounds.contains(mousePosition) {
        return index
      }
    }
    return nil
  }
}
