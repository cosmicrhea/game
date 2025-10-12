import GL
import GLFW
import GLMath

class InventoryView: RenderLoop {
  private let promptList = PromptList(.menu, axis: .horizontal)

  func draw() {
    promptList.draw()
  }
}
