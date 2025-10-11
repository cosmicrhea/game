//
//  TitleScreen.swift
//  Glass
//
//  Created by Freya Alminde on 10/11/25.
//

import GL
import GLFW
//import CGLFW3
import GLMath

struct MenuItem {
  var title: String
  var disabled: Bool = false
}

final class TitleScreen: RenderLoop {
  private var deltaTime: Float = 0.0

  private var selectedIndex: Int = 0
  private let menuItems = [
    MenuItem(title: "New Game"),
    MenuItem(title: "Continue", disabled: true),
    MenuItem(title: "Options"),
    MenuItem(title: "Give Up"),
  ]

  private let backgroundImage = Image("UI/title_screen.png")

  private let inputPrompts = InputPrompts()

  // Animation state
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var animationDuration: Float = 0.3
  private var previousSelectedIndex: Int = 0
  private let menuAnimationEasing: Easing = .easeOutCubic

  // Text styles
  private let titleStyle = TextStyle.titleScreen
  private let menuStyle = TextStyle.menuItem
  private let disabledMenuStyle = TextStyle.menuItemDisabled
  private let versionStyle = TextStyle.version

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime

    // Update animation
    if isAnimating {
      animationTime += deltaTime
      if animationTime >= animationDuration {
        animationTime = animationDuration
        isAnimating = false
      }
    }
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .up, .w:
      cycleSelection(direction: -1)
    case .down, .s:
      cycleSelection(direction: +1)
    case .enter, .space:
      handleMenuSelection()
    case .escape:
      break
    default:
      break
    }
  }

  private func cycleSelection(direction: Int) {
    let newIndex = (selectedIndex + direction + menuItems.count) % menuItems.count
    if newIndex != selectedIndex {
      startMenuAnimation(from: selectedIndex, to: newIndex)
      selectedIndex = newIndex
      UISound.navigate()
    }
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      handleMenuSelection()
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    let mouseX = Float(x)
    let mouseY = Float(HEIGHT) - Float(y)  // Flip Y coordinate
    let screenHeight = Float(HEIGHT)

    // Calculate menu bounds for mouse interaction
    let menuStartX: Float = 96
    let menuStartY: Float = screenHeight - 64 - (Float(menuItems.count) * 60)
    let menuSpacing: Float = 60
    let menuItemHeight: Float = 40  // Approximate height of menu items

    // Check if mouse is over any menu item
    for (index, _) in menuItems.enumerated() {
      let itemY = menuStartY + Float(menuItems.count - 1 - index) * menuSpacing
      let itemBounds = Rect(
        x: menuStartX,
        y: itemY,
        width: 300,  // Approximate width
        height: menuItemHeight
      )

      if itemBounds.contains(Point(mouseX, mouseY)) {
        if index != selectedIndex {
          startMenuAnimation(from: selectedIndex, to: index)
          selectedIndex = index
          UISound.navigate()
        }
        break
      }
    }
  }

  private func startMenuAnimation(from: Int, to: Int) {
    previousSelectedIndex = from
    animationTime = 0.0
    isAnimating = true
  }

  private func handleMenuSelection() {
    let selectedItem = menuItems[selectedIndex]
    print("Selected: \(selectedItem.title)")
    UISound.select()

    switch selectedItem.title {
    case "New Game":
      // TODO: Start new game
      print("Starting new game...")
    case "Continue":
      // TODO: Load saved game
      print("Loading saved game...")
    case "Options":
      // TODO: Open options menu
      print("Opening options...")
    case "Give Up":
      print("Exiting game...")
      // Wait 500ms before exiting
      Task {
        try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms in nanoseconds
        await MainActor.run {
          window.close()
        }
      }
    default:
      break
    }
  }

  func draw() {
    // Set clear color to black
    GraphicsContext.current?.renderer.setClearColor(.black)

    let screenWidth = Float(WIDTH)
    let screenHeight = Float(HEIGHT)

    // Draw background image
    let backgroundRect = Rect(x: 0, y: 0, width: screenWidth, height: screenHeight)
    backgroundImage.draw(in: backgroundRect)

    // Draw title "Glass" at the bottom (since Y=0 is at top) - HIDDEN FOR NOW
    // let titleText = "Glass"
    // let titleSize = titleText.size(with: titleStyle)
    // let titleX = (screenWidth - titleSize.width) / 2
    // let titleY = screenHeight - screenHeight * 0.25 - titleSize.height
    // titleText.draw(at: Point(titleX, titleY), style: titleStyle)

    // Draw menu options - left aligned with indentation for selected items (bottom-left)
    let menuStartX: Float = 96
    let menuStartY: Float = screenHeight - 64 - (Float(menuItems.count) * 60)  // 64px from bottom
    let menuSpacing: Float = 60
    let indentAmount: Float = 20  // Reduced from 28 to 20

    for (index, item) in menuItems.enumerated() {
      let isSelected = selectedIndex == index
      let isDisabled = item.disabled

      let baseStyle = isDisabled ? disabledMenuStyle : menuStyle
      let finalStyle: TextStyle

      if isSelected && !isDisabled {
        // Red text with dark red stroke for selected items
        finalStyle =
          baseStyle
          .withColor(.rose)
          .withStroke(width: 3, color: Color(0.3, 0.1, 0.1, 1.0))  // Dark red stroke
      } else if isSelected && isDisabled {
        // Dark red for disabled AND selected "Continue" item
        finalStyle =
          baseStyle
          .withColor(Color(0.4, 0.1, 0.1, 1.0))  // Dark red color
          .withStroke(width: 2, color: Color(0.2, 0.05, 0.05, 1.0))  // Darker red stroke
      } else if isDisabled {
        // Gray for disabled but not selected "Continue" item
        finalStyle = baseStyle.withColor(.gray500)
      } else {
        // Normal styling for unselected items
        let color: Color = .gray300
        finalStyle = baseStyle.withColor(color)
      }

      // Calculate animated position
      let baseX = menuStartX
      let baseY = menuStartY + Float(menuItems.count - 1 - index) * menuSpacing

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

      item.title.draw(at: Point(finalX, finalY), style: finalStyle)
    }

    // Draw version text in bottom left corner
//    let versionText = "Version 0.40 • Everything is subject to change"
    let versionText = "v0.41"
//    let versionSize = versionText.size(with: versionStyle)
    let versionX: Float = 56
    let versionY: Float = 20
    versionText.draw(at: Point(versionX, versionY), style: versionStyle, anchor: .bottomLeft)

    // Draw input prompts
    if let prompts = InputPromptGroups.groups["Menu Root"] {
      inputPrompts.drawHorizontal(
        prompts: prompts,
        inputSource: .keyboardMouse,
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        origin: (Float(WIDTH) - 56, 12),
        anchor: .bottomRight
      )
    }
  }
}
