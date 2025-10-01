import Foundation

final class FontsDemo: RenderLoop {

  private let fontRenderers: [(TextRenderer, FontLibrary.ResolvedFont)] = FontLibrary.availableFonts
    .compactMap { resolvedFont -> (TextRenderer, FontLibrary.ResolvedFont)? in
      guard let renderer = TextRenderer(resolvedFont.displayName) else { return nil }
      return (renderer, resolvedFont)
    }

  @MainActor func draw() {
    var yCursor: Float = 24

    // Original font demo first
    for (renderer, resolvedFont) in fontRenderers {
      yCursor += renderer.baselineFromTop
      renderer.draw(
        resolvedFont.baseName + ": The quick brown fox jumps over the lazy dog",
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT))
      )
      yCursor += renderer.descentFromBaseline + 8
    }

    // Add some space before outline test
    yCursor += 40

    // Test outline functionality
    if let testRenderer = TextRenderer("Determination") {
      testRenderer.scale = 2.0

      // Draw text with outline - bright yellow fill, dark purple outline
      testRenderer.draw(
        "OUTLINE TEST: The quick brown fox",
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        color: (0.863, 0.863, 0.808, 1.0),
        outlineColor: (0.278, 0.247, 0.341, 1.0),
        outlineThickness: 2.0
      )
      yCursor += testRenderer.scaledLineHeight + 8

      // Draw same text without outline for comparison
      testRenderer.draw(
        "NO OUTLINE: The quick brown fox",
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT)),
        color: (0.95, 0.95, 0.7, 1.0)  // Same bright yellow fill
      )
      yCursor += testRenderer.scaledLineHeight + 8
    }
  }
}

// Color(0.863, 0.863, 0.808)
// Color(0.278, 0.247, 0.341)
