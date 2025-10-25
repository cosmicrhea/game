@Editor final class FontsDemo: RenderLoop {
  @Editable(range: 16...32) var fontSize: Float = 24
  @Editable var danish: Bool = false

  private var fontStyles: [(TextStyle, Font.ResolvedFont)] {
    Font.availableFonts
      .compactMap { resolvedFont -> (TextStyle, Font.ResolvedFont)? in
        let style = TextStyle(fontName: resolvedFont.displayName, fontSize: fontSize, color: .white)
        return (style, resolvedFont)
      }
  }

  func draw() {
    var yCursor: Float = fontSize

    // Original font demo first
    for (style, resolvedFont) in fontStyles {
      let text =
        resolvedFont.baseName
        + (danish
          ? ": Quizdeltagerne spiste jordbær med fløde mens cirkusklovnen Walther spillede på xylofon"
          : ": The quick brown ███ fox jumps over the lazy dog — ° æøå")
      text.draw(
        at: Point(24, yCursor),
        style: style
      )
      yCursor += (fontSize * 1.33) + 8  // Approximate line height
    }

    //    // Add some space before outline test
    //    yCursor += 40
    //
    //    // Test outline functionality
    //    let testStyle = TextStyle(
    //      fontName: "Determination", fontSize: 48, color: Color(red: 0.863, green: 0.863, blue: 0.808, alpha: 1.0))
    //    let outlineStyle = TextStyle(
    //      fontName: "Determination", fontSize: 48, color: Color(red: 0.95, green: 0.95, blue: 0.7, alpha: 1.0))
    //
    //    // Draw text with outline - bright yellow fill, dark purple outline
    //    "OUTLINE TEST: The quick brown fox".draw(
    //      at: Point(24, yCursor),
    //      style: testStyle
    //    )
    //    yCursor += 64 + 8  // Approximate line height
    //
    //    // Draw same text without outline for comparison
    //    "NO OUTLINE: The quick brown fox".draw(
    //      at: Point(24, yCursor),
    //      style: outlineStyle
    //    )
    //    yCursor += 64 + 8  // Approximate line height
  }
}
