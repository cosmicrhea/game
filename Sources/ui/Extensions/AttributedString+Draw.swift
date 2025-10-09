import Foundation
import GL

extension AttributedString {
  /// Draws the attributed string at the specified point.
  /// - Parameters:
  ///   - point: The point to draw the text at.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(at point: Point, context: GraphicsContext? = nil) {
    // Temporary path: use legacy ModularTextRenderer via TextRenderer for GL
    guard let renderer = TextRenderer("Determination", 24) else { return }
    let window = (w: Int32(WIDTH), h: Int32(HEIGHT))

    // Map to legacy structure (color only); approximate stroke with outline
    let legacy = AttributedText(
      text: string,
      attributes: attributes.map { a in
        LegacyTextAttribute(
          range: a.range,
          color: a.color.map { ($0.red, $0.green, $0.blue, $0.alpha) },
          font: a.fontName
        )
      })

    let outlineColor = attributes.compactMap { $0.stroke?.color }.first
    let outlineThickness = attributes.compactMap { $0.stroke?.width }.first ?? 0

    renderer.draw(
      legacy,
      at: (point.x, point.y),
      windowSize: window,
      defaultColor: (1, 1, 1, 1),
      scale: nil,
      wrapWidth: nil,
      anchor: .topLeft,
      outlineColor: outlineColor.map { ($0.red, $0.green, $0.blue, $0.alpha) },
      outlineThickness: outlineThickness
    )
  }

  /// Draws the attributed string within the specified rectangle.
  /// - Parameters:
  ///   - rect: The rectangle to draw the text within.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(in rect: Rect, context: GraphicsContext? = nil) {
    draw(at: rect.origin, context: context)
  }
}
