import GL
import GLFW
import GLMath

/// Demo for testing the slot grid component
@MainActor
final class SlotGridDemo: RenderLoop {
  private let inputPrompts = InputPrompts()
  private var slotGrid: SlotGrid

  // Grid configuration
  private var gridColumns = 4
  private var gridRows = 5
  private var slotSize: Float = 80.0
  private var spacing: Float = 2.0

  // Slot appearance controls
  private var cornerRadius: Float = 12.0
  private var radialGradientStrength: Float = 0.3

  // Grid position - centered on X, slightly above center on Y
  private var gridPosition = Point(0, 0)  // Will be calculated in init

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

    // Center the grid on X axis, slightly above center on Y
    recenterGrid()
  }

  func update(deltaTime: Float) {
    // Update any animations or effects
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .w, .up:
      slotGrid.moveSelection(direction: .down)  // Fixed: W/Up moves down
    case .s, .down:
      slotGrid.moveSelection(direction: .up)  // Fixed: S/Down moves up
    case .a, .left:
      slotGrid.moveSelection(direction: .left)
    case .d, .right:
      slotGrid.moveSelection(direction: .right)
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
    case .r:
      // Reset to defaults
      gridColumns = 6
      gridRows = 4
      slotSize = 80.0
      spacing = 2.0
      cornerRadius = 12.0
      radialGradientStrength = 0.3
      slotGrid = SlotGrid(columns: gridColumns, rows: gridRows, slotSize: slotSize, spacing: spacing)
      slotGrid.cornerRadius = cornerRadius
      slotGrid.radialGradientStrength = radialGradientStrength

      // Re-center the grid
      recenterGrid()
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
      "WASD/Arrows: Navigate selection",
      "+/-: Change spacing",
      "Q/E: Corner radius",
      "Z/C: Radial gradient",
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
      "Corner Radius: \(Int(cornerRadius))px",
      "Radial Gradient: \(String(format: "%.2f", radialGradientStrength))",
      "Selected: \(slotGrid.selectedIndex)",
      "Hovered: \(slotGrid.hoveredIndex?.description ?? "none")",
    ]

    for (index, line) in info.enumerated() {
      line.draw(
        at: Point(Float(WIDTH) - 20, Float(HEIGHT) - 20 - Float(index * 20)),
        style: TextStyle(fontName: "Determination", fontSize: 16, color: .white),
        anchor: .topRight
      )
    }
  }
}
