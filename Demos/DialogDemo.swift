/// Demo showing the dialog view with typewriter animation
final class DialogDemo: RenderLoop {
  private let dialogView = DialogView()

  private let messages = [
    "Welcome to the dialog demo!",
    "This text will type out character by character.",
    "You can display messages that wrap to two lines maximum, centered at the bottom of the screen.",
    "The typewriter effect creates a nice reading experience.",
    "Click forward to repeat this sequence!",
  ]

  init() {
    dialogView.print(chunks: messages)
  }

  func update(deltaTime: Float) {
    dialogView.update(deltaTime: deltaTime)
  }

  func draw() {
    dialogView.draw()
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .f, .space, .enter, .numpadEnter:
      // Try to advance chunk first, then restart only if all chunks are finished
      if !dialogView.tryAdvance() && dialogView.isFinished {
        restartMessages()
      }
    default:
      break
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      // Try to advance chunk first, then restart only if all chunks are finished
      if !dialogView.tryAdvance() && dialogView.isFinished {
        restartMessages()
      }
    }
  }

  private func restartMessages() {
    dialogView.print(chunks: messages)
  }
}
