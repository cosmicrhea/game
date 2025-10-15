/// Demo showing how to use the Prompt struct to render individual icons
final class PromptDemo: RenderLoop {
  func draw() {
    // Create a prompt with the same structure as PromptGroup
    let skipPrompt = Prompt([["keyboard_tab_icon"], ["xbox_button_color_x"], ["playstation_button_color_square"]])

    // You can customize the appearance
    //    skipPrompt.targetIconHeight = 32
    //    skipPrompt.iconOpacity = 0.8
    //    skipPrompt.iconSpacing = 4

    // Get the size of the prompt
    let promptSize = skipPrompt.size()
    print("Prompt size: \(promptSize)")

    // Draw the prompt at a specific position
    let position = Point(100, 100)
    skipPrompt.draw(at: position)

    // You can also specify a different input source
    skipPrompt.draw(at: Point(200, 100), inputSource: .xbox)
    skipPrompt.draw(at: Point(300, 100), inputSource: .playstation)
  }
}
