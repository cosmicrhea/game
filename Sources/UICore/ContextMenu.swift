import GL
import GLFW
import GLMath

/// A modal context menu that can pop up anywhere on screen
@MainActor
public class ContextMenu {
  // MARK: - Menu Item
  public struct MenuItem {
    public let id: String
    public let label: String
    public let icon: String?
    public let isEnabled: Bool
    public let action: () -> Void

    public init(id: String, label: String, icon: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
      self.id = id
      self.label = label
      self.icon = icon
      self.isEnabled = isEnabled
      self.action = action
    }
  }

  // MARK: - Properties
  public private(set) var isVisible: Bool = false
  public private(set) var position: Point = Point(0, 0)
  public private(set) var selectedIndex: Int = 0

  // MARK: - Positioning
  public var appearsAtMousePosition: Bool = false
  public var anchor: MenuAnchor = .topRight

  private var menuItems: [MenuItem] = []
  private let itemHeight: Float = 32.0
  private let padding: Float = 8.0
  private let minWidth: Float = 120.0

  // MARK: - Colors
  public var backgroundColor = Color(0.15, 0.15, 0.15, 0.95)
  public var selectedItemColor = Color(0.25, 0.25, 0.25, 0.95)
  public var disabledItemColor = Color(0.1, 0.1, 0.1, 0.7)
  public var textColor = Color.white
  public var disabledTextColor = Color(0.5, 0.5, 0.5)
  public var borderColor = Color(0.4, 0.4, 0.4)

  // MARK: - Rendering
  private var panelEffect = GLScreenEffect("Common/ContextMenu")

  public init() {}

  // MARK: - Public Methods

  /// Show the context menu at the specified position
  public func show(
    at position: Point, items: [MenuItem], openedWithKeyboard: Bool = false, triggerSize: Size = Size(80, 80)
  ) {
    self.menuItems = items
    self.selectedIndex = openedWithKeyboard ? 0 : -1  // -1 means no selection for mouse
    self.isVisible = true

    // Calculate final position based on anchor
    self.position = calculateFinalPosition(from: position, triggerSize: triggerSize)
  }

  /// Hide the context menu
  public func hide() {
    isVisible = false
  }

  /// Update mouse position for hover effects
  public func updateMouse(at mousePosition: Point) {
    guard isVisible else { return }

    // Only update selection if mouse is inside the menu bounds
    if isMouseInsideMenu(at: mousePosition) {
      let relativeY = position.y - mousePosition.y  // Flipped: position.y - mousePosition.y
      let newIndex = Int(relativeY / itemHeight)

      if newIndex >= 0 && newIndex < menuItems.count {
        selectedIndex = newIndex
      }
    } else {
      // Clear selection when mouse leaves the menu
      selectedIndex = -1
    }
  }

  /// Check if mouse position is inside the menu bounds
  public func isMouseInsideMenu(at mousePosition: Point) -> Bool {
    let menuWidth = max(minWidth, calculateMenuWidth())
    let menuHeight = Float(menuItems.count) * itemHeight

    // Menu appears above the trigger point
    let menuTop = position.y - menuHeight
    let menuBottom = position.y
    let menuLeft = position.x
    let menuRight = position.x + menuWidth

    return mousePosition.x >= menuLeft && mousePosition.x <= menuRight && mousePosition.y >= menuTop
      && mousePosition.y <= menuBottom
  }

  /// Handle mouse click
  public func handleClick(at mousePosition: Point) -> Bool {
    guard isVisible else { return false }

    let relativeY = position.y - mousePosition.y  // Flipped: position.y - mousePosition.y
    let clickedIndex = Int(relativeY / itemHeight)

    if clickedIndex >= 0 && clickedIndex < menuItems.count {
      let item = menuItems[clickedIndex]
      if item.isEnabled {
        item.action()
        hide()
        return true
      }
    }

    return false
  }

  /// Handle keyboard navigation
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    guard isVisible else { return false }

    switch key {
    case .up, .w:
      selectedIndex = max(0, selectedIndex - 1)
      return true
    case .down, .s:
      selectedIndex = min(menuItems.count - 1, selectedIndex + 1)
      return true
    case .left, .a:
      return true
    case .right, .d:
      return true
    case .enter:
      if selectedIndex < menuItems.count {
        let item = menuItems[selectedIndex]
        if item.isEnabled {
          item.action()
          hide()
        }
      }
      return true
    case .escape:
      hide()
      return true
    default:
      return false
    }
  }

  // MARK: - Rendering

  /// Draw the context menu
  public func draw() {
    guard isVisible && !menuItems.isEmpty else { return }

    let menuWidth = max(minWidth, calculateMenuWidth())
    let menuHeight = Float(menuItems.count) * itemHeight

    // Draw background panel (flipped - panel appears above the trigger point)
    let centerPos = Point(
      position.x + menuWidth * 0.5,
      position.y - menuHeight * 0.5  // Flipped: subtract instead of add
    )

    panelEffect.draw { shader in
      shader.setVec2("uPanelSize", value: (menuWidth, menuHeight))
      shader.setVec2("uPanelCenter", value: (centerPos.x, centerPos.y))
      shader.setFloat("uBorderThickness", value: 2.0)
      shader.setFloat("uCornerRadius", value: 6.0)
      shader.setFloat("uNoiseScale", value: 0.02)
      shader.setFloat("uNoiseStrength", value: 0.1)

      // Set colors
      shader.setVec3("uPanelColor", value: (x: backgroundColor.red, y: backgroundColor.green, z: backgroundColor.blue))
      shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
      shader.setVec3("uBorderHighlight", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
      shader.setVec3("uBorderShadow", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
    }

    // Draw menu items (flipped - items appear above the trigger point)
    for (index, item) in menuItems.enumerated() {
      let itemY = position.y - Float(index + 1) * itemHeight  // Flipped: subtract instead of add
      let itemCenter = Point(position.x + menuWidth * 0.5, itemY + itemHeight * 0.5)

      // Draw selection highlight (only if selectedIndex is valid)
      if selectedIndex >= 0 && index == selectedIndex {
        panelEffect.draw { shader in
          shader.setVec2("uPanelSize", value: (menuWidth - 4, itemHeight - 2))
          shader.setVec2("uPanelCenter", value: (itemCenter.x, itemCenter.y))
          shader.setFloat("uBorderThickness", value: 0.0)
          shader.setFloat("uCornerRadius", value: 4.0)
          shader.setFloat("uNoiseScale", value: 0.0)
          shader.setFloat("uNoiseStrength", value: 0.0)

          // Set selection color
          shader.setVec3(
            "uPanelColor", value: (x: selectedItemColor.red, y: selectedItemColor.green, z: selectedItemColor.blue))
          shader.setVec3("uBorderColor", value: (x: 0, y: 0, z: 0))
          shader.setVec3("uBorderHighlight", value: (x: 0, y: 0, z: 0))
          shader.setVec3("uBorderShadow", value: (x: 0, y: 0, z: 0))
        }
      }

      // Draw item text - properly centered
      let textStyle = item.isEnabled ? TextStyle.contextMenu : TextStyle.contextMenuDisabled
      let textHeight = textStyle.fontSize * 1.2  // Approximate text height
      let textY = itemY + itemHeight - (itemHeight - textHeight) * 0.5  // Center vertically (flipped)

      item.label.draw(
        at: Point(position.x + padding, textY),
        style: textStyle,
        anchor: .topLeft
      )
    }
  }

  // MARK: - Private Methods

  private func calculateFinalPosition(from triggerPosition: Point, triggerSize: Size) -> Point {
    let menuWidth = max(minWidth, calculateMenuWidth())
    let menuHeight = Float(menuItems.count) * itemHeight

    var finalX = triggerPosition.x
    var finalY = triggerPosition.y

    // Adjust X position based on anchor
    switch anchor {
    case .topLeft, .left, .bottomLeft:
      finalX = triggerPosition.x - menuWidth  // Left of trigger
    case .top, .center, .bottom:
      finalX = triggerPosition.x - menuWidth * 0.5  // Centered on trigger
    case .topRight, .right, .bottomRight:
      finalX = triggerPosition.x + triggerSize.width * 0.5  // Right of trigger (menu's left edge at trigger's right edge)
    }

    // Adjust Y position based on anchor (OpenGL Y is flipped)
    switch anchor {
    case .topLeft, .top, .topRight:
      finalY = triggerPosition.y + triggerSize.height * 0.5  // Top of menu aligns with top of trigger
    case .left, .center, .right:
      finalY = triggerPosition.y - triggerSize.height * 0.5  // Centered vertically
    case .bottomLeft, .bottom, .bottomRight:
      finalY = triggerPosition.y - triggerSize.height  // Bottom of menu aligns with bottom of trigger
    }

    return Point(finalX, finalY)
  }

  private func calculateMenuWidth() -> Float {
    var maxWidth = minWidth

    for item in menuItems {
      // This is a rough calculation - in a real implementation you'd measure text width
      let estimatedWidth = Float(item.label.count) * 8.0 + padding * 2
      maxWidth = max(maxWidth, estimatedWidth)
    }

    return maxWidth
  }
}

// MARK: - MenuAnchor Enum
public enum MenuAnchor {
  case topLeft, top, topRight
  case left, center, right
  case bottomLeft, bottom, bottomRight
}
