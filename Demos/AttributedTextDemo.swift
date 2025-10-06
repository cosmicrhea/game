import Foundation

/// Demo showcasing attributed text rendering with colors and em-dashes
final class AttributedTextDemo: RenderLoop {

  @MainActor func draw() {
    var yCursor: Float = 24

    // Test 1: Basic attributed text with green highlighting
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 1.2

      let conversationText =
        "— This is Officer Mills! HQ, please respond!\n— This is HQ. What's the situation?\n— A new monster. They've got these glowing eyes, look like real creepy bastards!"

      // Create attributed text with green "glowing eyes"
      let attributedText = AttributedText.withGreenHighlight(conversationText, words: ["glowing eyes"])

      renderer.draw(
        attributedText,
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (0.9, 0.9, 0.9, 1.0),
        wrapWidth: 500
      )

      yCursor += 200
    }

    // Test 2: Multiple color highlights
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 1.0

      let text = "The quick brown fox jumps over the lazy dog."
      var attributedText = AttributedText(text: text)

      // Highlight different words with different colors
      attributedText = attributedText.withColor((1.0, 0.0, 0.0, 1.0), substring: "quick")
      attributedText = attributedText.withColor((0.0, 1.0, 0.0, 1.0), substring: "brown")
      attributedText = attributedText.withColor((0.0, 0.0, 1.0, 1.0), substring: "fox")
      attributedText = attributedText.withColor((1.0, 1.0, 0.0, 1.0), substring: "lazy")

      renderer.draw(
        attributedText,
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (0.8, 0.8, 0.8, 1.0)
      )

      yCursor += 60
    }

    // Test 3: Em-dash and special characters
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 1.1

      let text = "— Em-dash test: — — —\n— Multiple em-dashes in a row — — —\n— And some regular text too!"
      let attributedText = AttributedText(text: text)

      renderer.draw(
        attributedText,
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (0.9, 0.8, 0.9, 1.0)
      )

      yCursor += 120
    }

    // Test 4: Mixed attributed and plain text
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 1.0

      // Plain text
      renderer.draw(
        "Plain text: ",
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        color: (0.7, 0.7, 0.7, 1.0)
      )

      // Attributed text inline
      let attributedText = AttributedText.withColor("colored text", color: (1.0, 0.5, 0.0, 1.0))
      let plainWidth = renderer.measureWidth("Plain text: ")

      renderer.draw(
        attributedText,
        at: (24 + plainWidth, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (0.7, 0.7, 0.7, 1.0)
      )

      yCursor += 40
    }

    // Test 5: Line wrapping with attributed text
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 0.9

      let longText =
        "This is a very long line of attributed text that should wrap properly. It has some green words and some red words that should maintain their colors even when wrapped to multiple lines."
      var attributedText = AttributedText(text: longText)
      attributedText = attributedText.withColor((0.0, 1.0, 0.0, 1.0), substring: "green words")
      attributedText = attributedText.withColor((1.0, 0.0, 0.0, 1.0), substring: "red words")

      renderer.draw(
        attributedText,
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (0.8, 0.8, 0.8, 1.0),
        wrapWidth: 400
      )

      yCursor += 150
    }

    // Test 6: Outline with attributed text
    if let renderer = TextRenderer("Determination") {
      renderer.scale = 1.5

      let text = "OUTLINED ATTRIBUTED TEXT"
      let attributedText = AttributedText.withGreenHighlight(text, words: ["ATTRIBUTED"])

      renderer.draw(
        attributedText,
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        defaultColor: (1.0, 1.0, 1.0, 1.0),
        outlineColor: (0.2, 0.2, 0.4, 1.0),
        outlineThickness: 2.0
      )
    }
  }
}

