/// Demo for testing the global screen fade system
@MainActor
final class FadeDemo: RenderLoop {
  private let promptList = PromptList(.menu)
  private var screenFade = ScreenFadeFBO.shared

  init() {
    // Reset the screen fade to ensure clean state
    screenFade.reset()
  }

  func update(deltaTime: Float) {
    // Screen fade is updated by the main loop
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .space:
      // Toggle screen fade
      if screenFade.isVisible {
        screenFade.fadeFromBlack(duration: 3.0)
      } else {
        screenFade.fadeToBlack(duration: 3.0)
      }
    case .escape:
      // Reset to transparent
      screenFade.reset()
    default:
      break
    }
  }

  func draw() {
    // Simple dark background
    GraphicsContext.current?.renderer.setClearColor(.gray900)

    // Draw simple instructions
    let instructionText = "SPACE: Toggle fade | ESC: Reset"
    instructionText.draw(
      at: Point(20, Float(Engine.viewportSize.height) - 20),
      style: TextStyle(fontName: "Determination", fontSize: 24, color: .white),
      anchor: .topLeft
    )

    // Draw fade status
    let statusText = "Fade Opacity: \(String(format: "%.2f", screenFade.opacity))"
    statusText.draw(
      at: Point(20, Float(Engine.viewportSize.height) - 60),
      style: TextStyle(fontName: "Determination", fontSize: 20, color: .white),
      anchor: .topLeft
    )
  }
}
