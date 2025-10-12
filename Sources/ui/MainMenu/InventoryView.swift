import GL
import GLFW
import GLMath

class InventoryView: RenderLoop {
  private let inputPrompts = InputPrompts()

  func draw() {
    if let prompts = InputPromptGroups.groups["Menu"] {
      inputPrompts.drawHorizontal(
        prompts: prompts,
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        origin: (Float(WIDTH) - 56, 12),
        anchor: .bottomRight
      )
    }
  }
}
