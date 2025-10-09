import Foundation

/// Style configuration for text rendering.
public struct TextStyle: Sendable {
  /// Name of the font to use.
  public var fontName: String
  /// Size of the font in points.
  public var fontSize: Float
  /// Color of the text.
  public var color: Color

  /// Creates a new text style with the specified properties.
  /// - Parameters:
  ///   - fontName: Name of the font to use.
  ///   - fontSize: Size of the font in points.
  ///   - color: Color of the text.
  public init(fontName: String, fontSize: Float, color: Color) {
    self.fontName = fontName
    self.fontSize = fontSize
    self.color = color
  }
}

extension String {
  /// Draws the string at the specified point with the given style.
  /// - Parameters:
  ///   - point: The point to draw the text at.
  ///   - style: The text style to apply.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(at point: Point, style: TextStyle, context: GraphicsContext? = nil) {
    guard let renderer = TextRenderer(style.fontName, style.fontSize) else { return }
    let window = (w: Int32(WIDTH), h: Int32(HEIGHT))
    renderer.draw(
      self,
      at: (point.x, point.y),
      windowSize: window,
      color: (style.color.red, style.color.green, style.color.blue, style.color.alpha)
    )
  }

  /// Draws the string within the specified rectangle with the given style.
  /// - Parameters:
  ///   - rect: The rectangle to draw the text within.
  ///   - style: The text style to apply.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(in rect: Rect, style: TextStyle, context: GraphicsContext? = nil) {
    draw(at: rect.origin, style: style, context: context)
  }
}
