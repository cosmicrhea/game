import GL
import GLFW
import GLMath

@MainActor
final class InventoryView: RenderLoop {
  private let promptList = PromptList(.inventory)
  private var slotGrid: SlotGrid
  private let ambientBackground = GLScreenEffect("Effects/AmbientBackground")

  // Mouse tracking
  private var lastMouseX: Double = 0
  private var lastMouseY: Double = 0

  init() {
    slotGrid = SlotGrid(
      columns: 4,
      rows: 2,
      slotSize: 80.0,
      spacing: 4.0
    )
    slotGrid.onSlotAction = { [weak self] action, slotIndex in
      self?.handleSlotAction(action, slotIndex: slotIndex)
    }

    // Center the grid on X axis, slightly above center on Y
    recenterGrid()
  }

  /// Recalculate and set the grid position to keep it centered
  private func recenterGrid() {
    let totalSize = slotGrid.totalSize
    let gridPosition = Point(
      (Float(Engine.viewportSize.width) - totalSize.width) * 0.5,  // Center X
      (Float(Engine.viewportSize.height) - totalSize.height) * 0.5 + 80  // Slightly above center Y
    )
    slotGrid.setPosition(gridPosition)
  }

  func update(deltaTime: Float) {
    recenterGrid()

    // Update slot grid (includes menu animations)
    slotGrid.update(deltaTime: deltaTime)
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Let SlotGrid handle all input (including menu)
    if slotGrid.handleKey(key) {
      return
    }

    switch key {
    case .escape:
      // Exit inventory
      break
    default:
      break
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    lastMouseX = x
    lastMouseY = y
    // Flip Y coordinate to match screen coordinates (top-left origin)
    let mousePosition = Point(Float(x), Float(Engine.viewportSize.height) - Float(y))
    slotGrid.handleMouseMove(at: mousePosition)
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    let mousePosition = Point(Float(lastMouseX), Float(Engine.viewportSize.height) - Float(lastMouseY))

    if button == .left {
      _ = slotGrid.handleMouseClick(at: mousePosition)
    }
  }

  func draw() {
    // Draw ambient background
    ambientBackground.draw { shader in
      // Set ambient background parameters
      shader.setVec3("uTintDark", value: (0.035, 0.045, 0.055))
      shader.setVec3("uTintLight", value: (0.085, 0.10, 0.11))
      shader.setFloat("uMottle", value: 0.35)
      shader.setFloat("uGrain", value: 0.08)
      shader.setFloat("uVignette", value: 0.35)
      shader.setFloat("uDust", value: 0.06)
    }

    // Draw the slot grid (includes menu)
    slotGrid.draw()

    // Draw the prompt list
    promptList.draw()
  }

  // MARK: - Private Methods

  private func handleSlotAction(_ action: SlotAction, slotIndex: Int) {
    switch action {
    case .use:
      // Handle item use
      break
    case .inspect:
      // Handle item inspection
      break
    case .combine:
      // Handle item combination
      break
    case .discard:
      // Handle item discard
      break
    }
  }
}
