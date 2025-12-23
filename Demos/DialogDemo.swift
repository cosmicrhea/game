final class DialogDemo: RenderLoop {
  private let dialogView = DialogView()
  private var demoTask: Task<Void, Never>?

  init() {
    startDemo()
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
      dialogView.tryAdvance()
    default:
      break
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    if button == .left {
      dialogView.tryAdvance()
    }
  }

  private func startDemo() {
    demoTask?.cancel()
    demoTask = Task {
      await runDemo()
    }
  }

  private func runDemo() async {
    while !Task.isCancelled {
      // Initial ask
      let readyIndex = await dialogView.ask(
        "You ready for the demo?",
        options: ["Ready", "Not yet"]
      )

      if readyIndex == 1 {
        // If not ready, ask again
        continue
      }

      // Main demo messages
      await dialogView.print(chunks: [
        "Welcome to the dialog demo!",
        "This text will type out character by character.",
        "You can display messages that wrap to two lines maximum, centered at the bottom of the screen.",
        "The typewriter effect creates a nice reading experience.",
      ])

      // Final ask
      let answerIndex = await dialogView.ask(
        "Did you get all of that?",
        options: ["Got it", "Wait, what?"]
      )

      if answerIndex == 0 {
        await dialogView.print(chunks: ["Good. But since we're here, I'll tell you everything again anyway."])
        await dialogView.print(chunks: [])
      } else {
        await dialogView.print(chunks: ["Oh. Let me repeat."])
        await dialogView.print(chunks: [])
      }

      // Loop back to start
    }
  }
}
