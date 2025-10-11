import GL
import GLFW
import GLMath

/// Demo for testing the context menu system
@MainActor
final class ContextMenuDemo: RenderLoop {
  private let inputPrompts = InputPrompts()
  private var slotGrid: SlotGrid
  private var slotMenu: SlotMenu

  // Grid configuration
  private var gridColumns = 4
  private var gridRows = 3
  private var slotSize: Float = 80.0
  private var spacing: Float = 2.0

  // Menu state
  private var menuTriggeredSlot: Int? = nil
  private var lastAction: String = "No action yet"

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  init() {
    slotGrid = SlotGrid(
      columns: gridColumns,
      rows: gridRows,
      slotSize: slotSize,
      spacing: spacing
    )

    slotMenu = SlotMenu()

    // Center the grid
    let totalSize = slotGrid.totalSize
    let gridPosition = Point(
      (Float(WIDTH) - totalSize.width) * 0.5,
      (Float(HEIGHT) - totalSize.height) * 0.5
    )
    slotGrid.setPosition(gridPosition)

    // Set up slot menu action handler
    slotMenu.onAction = { [weak self] action, slotIndex in
      self?.handleSlotAction(action, slotIndex: slotIndex)
    }
  }

  func update(deltaTime: Float) {
    // Update any animations or effects
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Handle menu navigation if menu is visible
    if slotMenu.isVisible {
      if slotMenu.handleKey(key) {
        return
      }
    }

    switch key {
    case .w, .up:
      slotGrid.moveSelection(direction: .down)
    case .s, .down:
      slotGrid.moveSelection(direction: .up)
    case .a, .left:
      slotGrid.moveSelection(direction: .left)
    case .d, .right:
      slotGrid.moveSelection(direction: .right)
    case .enter:
      // Trigger menu for selected slot
      showMenuForSelectedSlot()
    case .escape:
      if slotMenu.isVisible {
        slotMenu.hide()
      }
    case .equal:
      spacing += 1
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      recenterGrid()
    case .minus:
      spacing = max(0, spacing - 1)
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      recenterGrid()
    case .r:
      // Reset
      gridColumns = 4
      gridRows = 3
      slotSize = 80.0
      spacing = 2.0
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      recenterGrid()
      slotMenu.hide()
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y

    // Flip Y coordinate to match screen coordinates
    let mousePos = Point(Float(x), Float(HEIGHT) - Float(y))

    if slotMenu.isVisible {
      slotMenu.updateMouse(at: mousePos)
    } else {
      slotGrid.updateHover(at: mousePos)
    }
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePos = Point(Float(lastMouseX), Float(HEIGHT) - Float(lastMouseY))

    if button == .left {
      if slotMenu.isVisible {
        // Handle menu click
        if slotMenu.handleClick(at: mousePos) {
          // Menu item was clicked, menu is now hidden
          return
        } else {
          // Clicked outside menu, hide it
          slotMenu.hide()
        }
      } else {
        // Select slot and show menu
        if let slotIndex = slotGrid.slotIndex(at: mousePos) {
          slotGrid.setSelected(slotIndex)
          showMenuForSlot(slotIndex, at: mousePos)
        }
      }
    }
  }

  func draw() {
    // Dark background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the slot grid
    slotGrid.draw()

    // Draw the context menu
    slotMenu.draw()

    // Draw instructions
    let instructions = [
      "WASD/Arrows: Navigate selection",
      "ENTER: Show menu for selected slot",
      "Mouse: Click slot to show menu",
      "Menu: WASD/Arrows to navigate, ENTER to select",
      "ESC: Close menu or exit",
      "+/-: Change spacing",
      "R: Reset",
    ]

    for (index, instruction) in instructions.enumerated() {
      instruction.draw(
        at: Point(20, Float(HEIGHT) - 20 - Float(index * 25)),
        style: TextStyle(fontName: "Determination", fontSize: 18, color: .white),
        anchor: .topLeft
      )
    }

    // Draw info
    let info = [
      "Grid: \(gridColumns)x\(gridRows)",
      "Spacing: \(Int(spacing))px",
      "Selected: \(slotGrid.selectedIndex)",
      "Hovered: \(slotGrid.hoveredIndex?.description ?? "none")",
      "Menu: \(slotMenu.isVisible ? "Visible" : "Hidden")",
      "Last Action: \(lastAction)",
    ]

    for (index, line) in info.enumerated() {
      line.draw(
        at: Point(Float(WIDTH) - 20, Float(HEIGHT) - 20 - Float(index * 20)),
        style: TextStyle(fontName: "Determination", fontSize: 16, color: .white),
        anchor: .topRight
      )
    }
  }

  // MARK: - Private Methods

  private func showMenuForSelectedSlot() {
    let selectedIndex = slotGrid.selectedIndex
    let slotPos = slotGrid.slotPosition(at: selectedIndex)
    let slotCenter = Point(
      slotPos.x + slotSize * 0.5,
      slotPos.y + slotSize * 0.5
    )
    showMenuForSlot(selectedIndex, at: slotCenter, openedWithKeyboard: true)
  }

  private func showMenuForSlot(_ slotIndex: Int, at position: Point, openedWithKeyboard: Bool = false) {
    let slotPos = slotGrid.slotPosition(at: slotIndex)
    // Use the slot's position instead of the mouse position for consistent positioning
    let slotCenter = Point(
      slotPos.x + slotSize * 0.5,
      slotPos.y + slotSize * 0.5
    )
    slotMenu.showForSlot(
      at: slotCenter,
      slotIndex: slotIndex,
      slotPosition: slotPos,
      availableActions: [.use, .inspect, .move, .discard],
      openedWithKeyboard: openedWithKeyboard,
      slotSize: Size(slotSize, slotSize)
    )
    menuTriggeredSlot = slotIndex
  }

  private func handleSlotAction(_ action: SlotMenu.SlotAction, slotIndex: Int) {
    switch action {
    case .use:
      lastAction = "Used slot \(slotIndex)"
    case .inspect:
      lastAction = "Inspected slot \(slotIndex)"
    case .move:
      lastAction = "Moved slot \(slotIndex)"
    case .discard:
      lastAction = "Discarded slot \(slotIndex)"
    }
  }

  private func recenterGrid() {
    let totalSize = slotGrid.totalSize
    let gridPosition = Point(
      (Float(WIDTH) - totalSize.width) * 0.5,
      (Float(HEIGHT) - totalSize.height) * 0.5
    )
    slotGrid.setPosition(gridPosition)
  }
}
