import GL
import GLFW
import GLMath

/// Demo for testing the slot grid component with context menu support
@MainActor
final class SlotGridDemo: RenderLoop {
  private let promptList = PromptList(.menu, axis: .horizontal)
  private var slotGrid: SlotGrid

  // Grid configuration
  private var gridColumns = 4
  private var gridRows = 5
  private var slotSize: Float = 80.0
  private var spacing: Float = 4.0

  // Slot appearance controls
  private var cornerRadius: Float = 12.0
  private var radialGradientStrength: Float = 0.3

  // Grid position - centered on X, slightly above center on Y
  private var gridPosition = Point(0, 0)  // Will be calculated in init

  // Menu state
  private var lastAction: String = "No action yet"

  /// Recalculate and set the grid position to keep it centered
  private func recenterGrid() {
    let totalSize = slotGrid.totalSize
    gridPosition = Point(
      (Float(WIDTH) - totalSize.width) * 0.5,  // Center X
      (Float(HEIGHT) - totalSize.height) * 0.5 + 80  // Slightly above center Y
    )
    slotGrid.setPosition(gridPosition)
  }

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
    slotGrid.onSlotAction = { [weak self] action, slotIndex in
      self?.handleSlotAction(action, slotIndex: slotIndex)
    }

    // Center the grid on X axis, slightly above center on Y
    recenterGrid()
  }

  func update(deltaTime: Float) {
    // Update slot grid (includes menu animations)
    slotGrid.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Let SlotGrid handle all input (including menu)
    if slotGrid.handleKey(key) {
      return
    }

    switch key {
    case .equal:
      spacing += 1
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      recenterGrid()
    case .minus:
      spacing = max(0, spacing - 1)
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      recenterGrid()
    case .q:
      cornerRadius += 1
      slotGrid.cornerRadius = cornerRadius
    case .e:
      cornerRadius = max(0, cornerRadius - 1)
      slotGrid.cornerRadius = cornerRadius
    case .z:
      radialGradientStrength = min(1.0, radialGradientStrength + 0.05)
      slotGrid.radialGradientStrength = radialGradientStrength
    case .c:
      radialGradientStrength = max(0.0, radialGradientStrength - 0.05)
      slotGrid.radialGradientStrength = radialGradientStrength
    case .t:
      // Toggle selection wrapping
      slotGrid.selectionWraps.toggle()
    case .r:
      // Reset to defaults
      gridColumns = 6
      gridRows = 4
      slotSize = 80.0
      spacing = 2.0
      cornerRadius = 12.0
      radialGradientStrength = 0.3
      slotGrid = SlotGrid(
        columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing, cornerRadius: cornerRadius,
        radialGradientStrength: radialGradientStrength)
      recenterGrid()
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y
    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(HEIGHT) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePosition = Point(Float(lastMouseX), Float(HEIGHT) - Float(lastMouseY))

    if button == .left {
      _ = slotGrid.handleMouseClick(at: mousePosition)
    }
  }

  func draw() {
    // Dark background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the slot grid (includes menu)
    slotGrid.draw()

    // Draw instructions
    let instructions = [
      "WASD/Arrows: Navigate selection",
      "ENTER: Show menu for selected slot",
      "Mouse: Click slot to show menu",
      "Menu: WASD/Arrows to navigate, ENTER to select",
      "ESC: Close menu or exit",
      "+/-: Change spacing",
      "Q/E: Corner radius",
      "Z/C: Radial gradient",
      "T: Toggle selection wrapping",
      "R: Reset to defaults",
    ]

    for (index, instruction) in instructions.enumerated() {
      instruction.draw(
        at: Point(20, Float(HEIGHT) - 20 - Float(index * 25)),
        style: TextStyle(fontName: "Determination", fontSize: 18, color: .white),
        anchor: .topLeft
      )
    }

    // Draw grid info
    let info = [
      "Grid: \(gridColumns)x\(gridRows)",
      "Slot Size: \(Int(slotSize))px",
      "Spacing: \(Int(spacing))px",
      "Corner Radius: \(Int(cornerRadius))px",
      "Radial Gradient: \(String(format: "%.2f", radialGradientStrength))",
      "Selection Wraps: \(slotGrid.selectionWraps ? "ON" : "OFF")",
      "Selected: \(slotGrid.selectedIndex)",
      "Hovered: \(slotGrid.hoveredIndex?.description ?? "none")",
      "Menu: \(slotGrid.slotMenu.isVisible ? "Visible" : "Hidden")",
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

  private func handleSlotAction(_ action: SlotAction, slotIndex: Int) {
    switch action {
    case .use:
      lastAction = "Used slot \(slotIndex)"
    case .inspect:
      lastAction = "Inspected slot \(slotIndex)"
    case .combine:
      lastAction = "Combined slot \(slotIndex)"
    case .discard:
      lastAction = "Discarded slot \(slotIndex)"
    }
  }
}
