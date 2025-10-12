import GLFW

final class TitleScreen: RenderLoop {
  private var deltaTime: Float = 0.0

  struct MenuItem {
    var title: String
    var disabled: Bool = false
  }

  private var selectedIndex: Int = 0
  private let menuItems = [
    MenuItem(title: "New Game"),
    MenuItem(title: "Continue", disabled: true),
    MenuItem(title: "Options"),
    MenuItem(title: "Give Up"),
  ]

  private let backgroundImage = Image("UI/title_screen.png")

  private let promptList = PromptList(.menuRoot, axis: .horizontal)

  // Animation state
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var animationDuration: Float = 0.3
  private var previousSelectedIndex: Int = 0
  private let menuAnimationEasing: Easing = .easeOutCubic

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
    case .up, .w: cycleSelection(direction: -1)
    case .down, .s: cycleSelection(direction: +1)
    case .enter, .space: handleMenuSelection()
    case .escape: break
    default: break
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
      Task { @MainActor in
        #if os(macOS)
          Engine.shared.window.nsWindow?.animationBehavior = .utilityWindow
          Engine.shared.window.nsWindow?.close()
          try? await Task.sleep(nanoseconds: 500_000_000)
        #endif

        Engine.shared.window.close()
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
    // let titleSize = titleText.size(with: .titleScreen)
    // let titleX = (screenWidth - titleSize.width) / 2
    // let titleY = screenHeight - screenHeight * 0.25 - titleSize.height
    // titleText.draw(at: Point(titleX, titleY), style: .titleScreen)

    // Draw menu options - left aligned with indentation for selected items (bottom-left)
    let menuStartX: Float = 96
    let menuStartY: Float = screenHeight - 64 - (Float(menuItems.count) * 60)  // 64px from bottom
    let menuSpacing: Float = 60
    let indentAmount: Float = 20  // Reduced from 28 to 20

    for (index, item) in menuItems.enumerated() {
      let isSelected = selectedIndex == index
      let isDisabled = item.disabled

      let finalStyle = TextStyle.menuItem(selected: isSelected, disabled: isDisabled)

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
    let versionText = "v\(Engine.versionString)"
    let versionX: Float = 56
    let versionY: Float = 20
    versionText.draw(at: Point(versionX, versionY), style: .version, anchor: .bottomLeft)

    // Draw input prompts
    promptList.draw()
  }
}
