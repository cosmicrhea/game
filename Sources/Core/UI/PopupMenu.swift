import Foundation
import GL
import GLFW
import GLMath

// MenuAnchor has been replaced with the centralized Alignment enum in Geometry.swift

// MARK: - Menu Item
public struct MenuItem {
  public let id: String
  public let label: String
  public let icon: Image?
  public let isEnabled: Bool
  public let action: () -> Void

  public init(id: String, label: String, icon: Image? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
    self.id = id
    self.label = label
    self.icon = icon
    self.isEnabled = isEnabled
    self.action = action
  }
}

/// A modal popup menu that can appear anywhere on screen
@MainActor
public class PopupMenu {

  // MARK: - Properties
  public private(set) var isVisible: Bool = false
  public private(set) var position: Point = Point(0, 0)
  public private(set) var selectedIndex: Int = 0

  // MARK: - Positioning
  public var appearsAtMousePosition: Bool = false
  public var anchor: AnchorPoint = .topRight
  public var offset: Point = Point(0, 0)

  // MARK: - Animation
  public var showDuration: Float = 0.1
  public var hideDuration: Float = 0.15
  private var animationProgress: Float = 0.0
  private var isAnimating: Bool = false
  private var animationStartTime: Double = 0.0
  private var targetPosition: Point = .zero
  private var startPosition: Point = .zero
  private var currentTriggerSize: Size = .zero

  private var menuItems: [MenuItem] = []
  private let itemHeight: Float = 40.0
  private let padding: Float = 9.0
  private let minWidth: Float = 144.0

  // MARK: - Colors
  public var backgroundColor = Color(0.35, 0.35, 0.35, 0.75)
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
    at position: Point,
    items: [MenuItem],
    openedWithKeyboard: Bool = false,
    triggerSize: Size = Size(80, 80)
  ) {
    self.menuItems = items
    self.selectedIndex = openedWithKeyboard ? 0 : -1  // -1 means no selection for mouse
    self.isVisible = true

    // Store trigger size for animation
    self.currentTriggerSize = triggerSize

    // Calculate final position based on anchor
    self.targetPosition = calculateFinalPosition(from: position, triggerSize: triggerSize)

    // Start animation
    startShowAnimation()
  }

  /// Hide the context menu
  public func hide() {
    startHideAnimation()
  }

  /// Update animation (call this every frame)
  public func update(deltaTime: Float) {
    guard isAnimating else { return }

    let currentTime = Date().timeIntervalSince1970
    let elapsed = Float(currentTime - animationStartTime)

    // Use different duration for show vs hide
    let duration = isVisible ? showDuration : hideDuration
    let progress = min(elapsed / duration, 1.0)

    if progress >= 1.0 {
      // Animation complete
      isAnimating = false
      if !isVisible {
        // Hide animation complete, actually hide
        return
      }
    }

    // Update animation progress
    animationProgress = progress
    updateAnimationPosition()
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
        UISound.select()
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
      if selectedIndex > 0 {
        selectedIndex -= 1
      } else {
        selectedIndex = menuItems.count - 1  // Wrap to last item
      }
      UISound.navigate()
      return true
    case .down, .s:
      if selectedIndex < menuItems.count - 1 {
        selectedIndex += 1
      } else {
        selectedIndex = 0  // Wrap to first item
      }
      UISound.navigate()
      return true
    case .left, .a:
      return true
    case .right, .d:
      return true
    case .f, .space, .enter:
      if selectedIndex < menuItems.count {
        let item = menuItems[selectedIndex]
        if item.isEnabled {
          item.action()
          UISound.select()
          hide()
        }
      }
      return true
    case .escape:
      UISound.cancel()
      hide()
      return true
    default:
      return false
    }
  }

  // MARK: - Rendering

  /// Draw the context menu
  public func draw() {
    guard (isVisible || isAnimating) && !menuItems.isEmpty else { return }

    let menuWidth = max(minWidth, calculateMenuWidth())
    let menuHeight = Float(menuItems.count) * itemHeight

    // Draw background panel (flipped - panel appears above the trigger point)
    let centerPosition = Point(
      position.x + menuWidth * 0.5,
      position.y - menuHeight * 0.5  // Flipped: subtract instead of add
    )

    // Calculate fade alpha based on animation
    let fadeAlpha = isVisible ? animationProgress : (1.0 - animationProgress)
    let currentBackgroundColor = backgroundColor.withAlphaComponent(fadeAlpha)

    panelEffect.draw { shader in
      shader.setVec2("uPanelSize", value: (menuWidth, menuHeight))
      shader.setVec2("uPanelCenter", value: (centerPosition.x, centerPosition.y))
      shader.setFloat("uBorderThickness", value: 2.0)
      shader.setFloat("uCornerRadius", value: 7.0)
      shader.setFloat("uNoiseScale", value: 0.02)
      shader.setFloat("uNoiseStrength", value: 0.1)

      // Set colors with fade
      shader.setVec4(
        "uPanelColor",
        value: (
          x: currentBackgroundColor.red, y: currentBackgroundColor.green, z: currentBackgroundColor.blue,
          w: currentBackgroundColor.alpha
        ))
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

      // Draw icon if present
      let iconSize: Float = 20.0
      let iconPadding: Float = 8.0
      if let icon = item.icon {
        let iconY = itemY + (itemHeight - iconSize) * 0.5  // Center vertically
        let iconRect = Rect(
          x: position.x + iconPadding,
          y: iconY,
          width: iconSize,
          height: iconSize
        )

        // Apply fade to icon
        let fadeAlpha = isVisible ? animationProgress : (1.0 - animationProgress)
        let iconTint = Color.white.withAlphaComponent(fadeAlpha)
        icon.draw(in: iconRect, tint: iconTint)
      }

      // Draw item text - properly centered with fade
      let textStyle = item.isEnabled ? TextStyle.contextMenu : TextStyle.contextMenuDisabled
      let textHeight = textStyle.fontSize * 1.2  // Approximate text height
      let textY = itemY + itemHeight - (itemHeight - textHeight) * 0.5  // Center vertically (flipped)

      // Apply fade to text color
      let fadeAlpha = isVisible ? animationProgress : (1.0 - animationProgress)
      let fadedTextColor = Color(
        textStyle.color.red,
        textStyle.color.green,
        textStyle.color.blue,
        textStyle.color.alpha * fadeAlpha
      )

      // Create faded text style
      let fadedTextStyle = TextStyle(
        fontName: textStyle.fontName,
        fontSize: textStyle.fontSize,
        color: fadedTextColor
      )

      // Adjust text position based on whether there's an icon
      let textX = item.icon != nil ? position.x + iconPadding + iconSize + 8 : position.x + padding
      item.label.draw(
        at: Point(textX, textY),
        style: fadedTextStyle,
        anchor: .topLeft
      )
    }

    // Note: For proper framebuffer fading, we'd need to:
    // 1. Render the menu to a framebuffer
    // 2. Apply fade effect to the framebuffer
    // 3. Blit the faded result to screen
    // For now, we're using alpha blending on individual elements
  }

  // MARK: - Private Methods

  private func startShowAnimation() {
    isAnimating = true
    animationStartTime = Date().timeIntervalSince1970
    animationProgress = 0.0

    // Start position based on anchor (slide in from the side)
    let slideDistance = currentTriggerSize.width / 3.0  // One third of trigger width

    switch anchor {
    case .topLeft, .left, .bottomLeft:
      startPosition = Point(targetPosition.x + slideDistance, targetPosition.y)  // Slide from right (flipped)
    case .top, .center, .bottom:
      startPosition = Point(targetPosition.x, targetPosition.y - 50)  // Slide from top
    case .topRight, .right, .bottomRight:
      startPosition = Point(targetPosition.x - slideDistance, targetPosition.y)  // Slide from left (flipped)
    case .baselineLeft:
      startPosition = Point(targetPosition.x + slideDistance, targetPosition.y)  // Slide from right (flipped)
    }

    position = startPosition
  }

  private func startHideAnimation() {
    isAnimating = true
    animationStartTime = Date().timeIntervalSince1970
    animationProgress = 0.0
    isVisible = false  // Hide immediately but animate out
  }

  private func updateAnimationPosition() {
    if isVisible {
      // Show animation: quick and snappy
      let easedProgress = Easing.easeOutCirc.apply(animationProgress)
      position = Point(
        lerp(startPosition.x, targetPosition.x, easedProgress),
        lerp(startPosition.y, targetPosition.y, easedProgress)
      )
    } else {
      // Hide animation: slower and smooth
      let easedProgress = Easing.easeInCubic.apply(animationProgress)
      let hideStartPosition = targetPosition
      let hideEndPosition = startPosition
      position = Point(
        lerp(hideStartPosition.x, hideEndPosition.x, easedProgress),
        lerp(hideStartPosition.y, hideEndPosition.y, easedProgress)
      )
    }
  }

  private func calculateFinalPosition(from triggerPosition: Point, triggerSize: Size) -> Point {
    let menuWidth = max(minWidth, calculateMenuWidth())
    // let menuHeight = Float(menuItems.count) * itemHeight

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
    case .baselineLeft:
      finalX = triggerPosition.x - menuWidth  // Left of trigger
    }

    // Adjust Y position based on anchor (OpenGL Y is flipped)
    switch anchor {
    case .topLeft, .top, .topRight:
      finalY = triggerPosition.y + triggerSize.height * 0.5  // Top of menu aligns with top of trigger
    case .left, .center, .right:
      finalY = triggerPosition.y - triggerSize.height * 0.5  // Centered vertically
    case .bottomLeft, .bottom, .bottomRight:
      finalY = triggerPosition.y - triggerSize.height  // Bottom of menu aligns with bottom of trigger
    case .baselineLeft:
      finalY = triggerPosition.y + triggerSize.height * 0.5  // Top of menu aligns with top of trigger
    }

    return Point(finalX + offset.x, finalY + offset.y)
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
