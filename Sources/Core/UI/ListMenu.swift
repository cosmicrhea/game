/// A reusable menu component that can be used in different screens
@MainActor
public class ListMenu {
  // MARK: - MenuItem
  public struct MenuItem {
    public let id: String
    public let label: String
    public let isEnabled: Bool
    public let action: () -> Void

    public init(id: String, label: String, isEnabled: Bool = true, action: @escaping () -> Void) {
      self.id = id
      self.label = label
      self.isEnabled = isEnabled
      self.action = action
    }
  }

  // MARK: - Properties
  public private(set) var selectedIndex: Int = 0
  public private(set) var menuItems: [MenuItem] = []

  // MARK: - Positioning
  public var position: Point = Point(96, 0)  // Default left-aligned position
  public var spacing: Float = 60
  public var indentAmount: Float = 20

  // MARK: - Animation
  public var animationDuration: Float = 0.3
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var previousSelectedIndex: Int = 0
  private let menuAnimationEasing: Easing = .easeOutCubic

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
    case .enter, .space:
      handleMenuSelection()
      return true
    default:
      return false
    }
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

    let screenHeight = Float(Engine.viewportSize.height)
    let menuStartY = screenHeight - 64 - (Float(menuItems.count) * spacing)

    for (index, item) in menuItems.enumerated() {
      let isSelected = selectedIndex == index
      let isDisabled = !item.isEnabled

      let finalStyle = TextStyle.menuItem(selected: isSelected, disabled: isDisabled)

      // Calculate animated position
      let baseX = position.x
      let baseY = menuStartY + Float(menuItems.count - 1 - index) * spacing

      var finalX = baseX
      let finalY = baseY

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

      item.label.draw(at: Point(finalX, finalY), style: finalStyle)
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
    let screenHeight = Float(Engine.viewportSize.height)
    let menuStartY = screenHeight - 64 - (Float(menuItems.count) * spacing)
    let menuItemHeight: Float = 40

    for (index, _) in menuItems.enumerated() {
      let itemY = menuStartY + Float(menuItems.count - 2 - index) * spacing
      let itemBounds = Rect(
        x: position.x,
        y: itemY,
        width: 300,  // Approximate width
        height: menuItemHeight
      )

      if itemBounds.contains(mousePosition) {
        return index
      }
    }
    return nil
  }
}
