//import Foundation
//
///// Demo showcasing advanced text rendering features
//final class TextDemo: RenderLoop {
//
//  @MainActor func draw() {
//    var yCursor: Float = 24
//
//    // Test 1: Basic text rendering
//    if let renderer = TextRenderer("Determination") {
//      renderer.scale = 1.5
//      renderer.draw(
//        "Basic Text Rendering Test",
//        at: (24, yCursor),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (0.9, 0.9, 0.9, 1.0)
//      )
//      yCursor += renderer.scaledLineHeight + 40  // More space between tests
//    }
//
//    // Test 2: Line wrapping
//    if let renderer = TextRenderer("Determination") {
//      renderer.scale = 1.2
//      let longText =
//        "This is a very long line of text that should wrap to multiple lines when the wrap width is set. It should handle word boundaries correctly and not start lines with spaces."
//
//      renderer.draw(
//        longText,
//        at: (24, yCursor),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (0.8, 0.9, 1.0, 1.0),
//        wrapWidth: 400,
//        anchor: .topLeft
//      )
//      yCursor += 200  // More space for wrapped text
//    }
//
//    // Test 3: Different anchors
//    if let renderer = TextRenderer("Determination") {
//      renderer.scale = 1.0
//      let testY = yCursor + 100
//
//      // Top-left anchor
//      renderer.draw(
//        "Top-Left",
//        at: (24, testY),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (1.0, 0.8, 0.8, 1.0),
//        anchor: .topLeft
//      )
//
//      // Bottom-left anchor
//      renderer.draw(
//        "Bottom-Left",
//        at: (200, testY),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (0.8, 1.0, 0.8, 1.0),
//        anchor: .bottomLeft
//      )
//
//      // Baseline-left anchor
//      renderer.draw(
//        "Baseline-Left",
//        at: (400, testY),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (0.8, 0.8, 1.0, 1.0),
//        anchor: .baselineLeft
//      )
//
//      yCursor += 200  // More space for anchor test
//    }
//
//    // Test 4: Outline rendering
//    if let renderer = TextRenderer("Determination") {
//      renderer.scale = 2.0
//      renderer.draw(
//        "OUTLINE TEST",
//        at: (24, yCursor),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (1.0, 1.0, 0.8, 1.0),
//        outlineColor: (0.2, 0.2, 0.4, 1.0),
//        outlineThickness: 3.0
//      )
//      yCursor += renderer.scaledLineHeight + 40
//    }
//
//    // Test 5: Different scales
//    if let renderer = TextRenderer("Determination") {
//      let scales: [Float] = [0.8, 1.0, 1.5, 2.0]
//      let colors: [(Float, Float, Float, Float)] = [
//        (0.7, 0.7, 0.7, 1.0),
//        (0.8, 0.8, 0.8, 1.0),
//        (0.9, 0.9, 0.9, 1.0),
//        (1.0, 1.0, 1.0, 1.0),
//      ]
//
//      for (i, scale) in scales.enumerated() {
//        renderer.scale = scale
//        renderer.draw(
//          "Scale \(scale)",
//          at: (24, yCursor),
//          windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//          color: colors[i]
//        )
//        yCursor += renderer.scaledLineHeight + 10  // More space between scale tests
//      }
//    }
//
//    // Test 6: Edge cases for line wrapping
//    if let renderer = TextRenderer("Determination") {
//      renderer.scale = 1.0
//      let edgeCaseText = "   Leading spaces should be trimmed.   \n\nMultiple newlines.\n\n   Trailing spaces too.   "
//
//      renderer.draw(
//        edgeCaseText,
//        at: (24, yCursor),
//        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
//        color: (1.0, 0.9, 0.8, 1.0),
//        wrapWidth: 300
//      )
//    }
//  }
//}
