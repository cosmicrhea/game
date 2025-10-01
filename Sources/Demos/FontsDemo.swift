import Foundation

final class FontsDemo: Demo {

  private let fontRenderers: [(TextRenderer, FontLibrary.ResolvedFont)] = FontLibrary.availableFonts
    .compactMap { resolvedFont -> (TextRenderer, FontLibrary.ResolvedFont)? in
      guard let renderer = TextRenderer(resolvedFont.displayName) else { return nil }
      return (renderer, resolvedFont)
    }

  @MainActor func draw() {
    var yCursor: Float = 24
    for (renderer, resolvedFont) in fontRenderers {
      yCursor += renderer.baselineFromTop
      renderer.draw(
        resolvedFont.baseName + ": triangle is the key",
        at: (24, yCursor),
        windowSize: (Int32(WIDTH), Int32(HEIGHT))
      )
      yCursor += renderer.descentFromBaseline + 8
    }
  }
}
