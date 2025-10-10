import GL
import GLFW
import GLMath

@MainActor
final class TextEffectsDemo: RenderLoop {
  @ConfigValue("TextEffectsDemo/currentEffect")
  private var currentEffect: Int = 0

  private let effects = [
    "Plain Text",
    "Outline Only",
    "Shadow Only",
    "Outline + Shadow",
    "Thick Outline",
    "Soft Shadow",
  ]

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .space:
      currentEffect = (currentEffect + 1) % effects.count
      print("Switched to: \(effects[currentEffect]) (effect #\(currentEffect))")
    case .escape:
      window.shouldClose = true
    default:
      break
    }
  }

  func draw() {
    guard let context = GraphicsContext.current else { return }

    // Clear screen
    glClearColor(0.1, 0.1, 0.2, 1.0)
    glClear(GL_COLOR_BUFFER_BIT)

    // Create test text with different effects
    let testText = "Text Effects Demo\nPress SPACE to cycle effects"
    let style = TextStyle(
      fontName: "Better VCR",
      fontSize: 24,
      color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
      alignment: .center
    )

    // Create attributed string based on current effect
    var attributedString = AttributedString(string: testText)

    switch currentEffect {
    case 0:  // Plain Text
      // No additional attributes
      break

    case 1:  // Outline Only
      attributedString = attributedString.withStroke(
        width: 3.0,
        color: Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
        range: testText.startIndex..<testText.endIndex
      )

    case 2:  // Shadow Only
      attributedString = attributedString.withShadow(
        width: 3.0,
        offset: Point(4, -4),
        color: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.8),
        range: testText.startIndex..<testText.endIndex
      )

    case 3:  // Outline + Shadow
      attributedString =
        attributedString
        .withStroke(
          width: 2.0,
          color: Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
          range: testText.startIndex..<testText.endIndex
        )
        .withShadow(
          width: 2.0,
          offset: Point(3, -3),
          color: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6),
          range: testText.startIndex..<testText.endIndex
        )

    case 4:  // Thick Outline
      attributedString = attributedString.withStroke(
        width: 4.0,
        color: Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),
        range: testText.startIndex..<testText.endIndex
      )

    case 5:  // Soft Shadow
      attributedString = attributedString.withShadow(
        width: 5.0,
        offset: Point(4, -4),
        color: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.3),
        range: testText.startIndex..<testText.endIndex
      )

    default:
      break
    }

    // Draw the text
    attributedString.draw(
      at: Point(400, 300),
      defaultStyle: style,
      wrapWidth: 800,
      anchor: .topLeft,
      context: context
    )

    // Draw effect name
    let effectName = effects[currentEffect]
    let effectStyle = TextStyle(
      fontName: "Better VCR",
      fontSize: 16,
      color: Color(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0),
      alignment: .center
    )

    effectName.draw(
      at: Point(400, 400),
      style: effectStyle,
      context: context
    )
  }
}
