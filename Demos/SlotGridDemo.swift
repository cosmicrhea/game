import GL
import GLFW
import GLMath

/// Demo for testing the slot grid component
@MainActor
final class SlotGridDemo: RenderLoop {
  private let inputPrompts = InputPrompts()
  private var slotGrid: SlotGrid

  // Grid configuration
  private var gridColumns = 6
  private var gridRows = 4
  private var slotSize: Float = 80.0
  private var spacing: Float = 2.0

  // Grid position - centered on X, slightly above center on Y
  private var gridPosition = Point(0, 0)  // Will be calculated in init

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

    // Center the grid on X axis, slightly above center on Y
    let totalSize = slotGrid.totalSize
    gridPosition = Point(
      (Float(WIDTH) - totalSize.width) * 0.5,  // Center X
      (Float(HEIGHT) - totalSize.height) * 0.5 - 50  // Slightly above center Y
    )
    slotGrid.setPosition(gridPosition)
  }

  func update(deltaTime: Float) {
    // Update any animations or effects
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .w:
      slotGrid.moveSelection(direction: .down)  // Fixed: W moves down
    case .s:
      slotGrid.moveSelection(direction: .up)  // Fixed: S moves up
    case .a:
      slotGrid.moveSelection(direction: .left)
    case .d:
      slotGrid.moveSelection(direction: .right)
    case .equal:
      spacing += 1
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      slotGrid.setPosition(gridPosition)
    case .minus:
      spacing = max(0, spacing - 1)
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      slotGrid.setPosition(gridPosition)
    case .r:
      // Reset to defaults
      gridColumns = 6
      gridRows = 4
      slotSize = 80.0
      spacing = 2.0
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)

      // Re-center the grid
      let totalSize = slotGrid.totalSize
      gridPosition = Point(
        (Float(WIDTH) - totalSize.width) * 0.5,  // Center X
        (Float(HEIGHT) - totalSize.height) * 0.5 - 50  // Slightly above center Y
      )
      slotGrid.setPosition(gridPosition)
    case .escape:
      break
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y
    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePos = Point(Float(x), Float(HEIGHT) - Float(y))
    slotGrid.updateHover(at: mousePos)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      // Use the last known mouse position from onMouseMove (already flipped)
      let mousePos = Point(Float(lastMouseX), Float(HEIGHT) - Float(lastMouseY))
      if let slotIndex = slotGrid.slotIndex(at: mousePos) {
        slotGrid.setSelected(slotIndex)
      }
    }
  }

  func draw() {
    // Dark background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the slot grid
    slotGrid.draw()

    // Draw instructions
    let instructions = [
      "WASD: Navigate selection",
      "+/-: Change spacing",
      "Mouse: Hover & click slots",
      "R: Reset to defaults",
      "ESC: Exit",
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
      "Selected: \(slotGrid.selectedIndex)",
      "Hovered: \(slotGrid.hoveredIndex?.description ?? "none")",
    ]

    for (index, line) in info.enumerated() {
      line.draw(
        at: Point(Float(WIDTH) - 20, Float(HEIGHT) - 20 - Float(index * 20)),
        style: TextStyle(fontName: "Determination", fontSize: 16, color: .white),
        anchor: .topLeft
      )
    }
  }
}
