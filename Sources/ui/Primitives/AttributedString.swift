import Foundation
import GL

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

/// Stroke configuration for text rendering.
public struct TextStroke: Equatable {
  /// The width of the stroke in points.
  public var width: Float
  /// The color of the stroke.
  public var color: Color

  /// Creates a new text stroke with the specified width and color.
  /// - Parameters:
  ///   - width: The width of the stroke in points.
  ///   - color: The color of the stroke.
  public init(width: Float, color: Color) {
    self.width = width
    self.color = color
  }
}

/// Shadow configuration for text rendering.
public struct TextShadow: Equatable {
  /// The blur radius of the shadow in points.
  public var width: Float
  /// The offset of the shadow from the text.
  public var offset: Point
  /// The color of the shadow.
  public var color: Color

  /// Creates a new text shadow with the specified properties.
  /// - Parameters:
  ///   - width: The blur radius of the shadow in points.
  ///   - offset: The offset of the shadow from the text.
  ///   - color: The color of the shadow.
  public init(width: Float, offset: Point, color: Color) {
    self.width = width
    self.offset = offset
    self.color = color
  }
}

/// Represents a set of inline attributes applied to a specific range of text.
public struct TextAttribute {
  /// The range of characters this attribute applies to.
  public let range: Range<String.Index>
  /// The color of the text in this range.
  public let color: Color?
  /// The font name for this range.
  public let fontName: String?
  /// The font size for this range.
  public let fontSize: Float?
  /// The stroke configuration for this range.
  public let stroke: TextStroke?
  /// The shadow configuration for this range.
  public let shadow: TextShadow?

  /// Creates a new text attribute with the specified properties.
  /// - Parameters:
  ///   - range: The range of characters this attribute applies to.
  ///   - color: The color of the text in this range.
  ///   - fontName: The font name for this range.
  ///   - fontSize: The font size for this range.
  ///   - stroke: The stroke configuration for this range.
  ///   - shadow: The shadow configuration for this range.
  public init(
    range: Range<String.Index>,
    color: Color? = nil,
    fontName: String? = nil,
    fontSize: Float? = nil,
    stroke: TextStroke? = nil,
    shadow: TextShadow? = nil
  ) {
    self.range = range
    self.color = color
    self.fontName = fontName
    self.fontSize = fontSize
    self.stroke = stroke
    self.shadow = shadow
  }
}

/// Cross-platform attributed string subset tailored for HUD/UI rendering.
public struct AttributedString {
  /// The underlying string content.
  public let string: String
  /// The attributes applied to ranges of the string.
  public let attributes: [TextAttribute]

  /// Creates a new attributed string with the specified content and attributes.
  /// - Parameters:
  ///   - string: The string content.
  ///   - attributes: The attributes to apply to the string.
  public init(string: String, attributes: [TextAttribute] = []) {
    self.string = string
    self.attributes = attributes
  }
}

// MARK: - Builders
extension AttributedString {
  public static func withColor(_ string: String, color: Color) -> AttributedString {
    AttributedString(
      string: string,
      attributes: [TextAttribute(range: string.startIndex..<string.endIndex, color: color)]
    )
  }

  public func withColor(_ color: Color, range: Range<String.Index>) -> AttributedString {
    let a = TextAttribute(range: range, color: color)
    return AttributedString(string: string, attributes: attributes + [a])
  }

  public func withFont(name: String, size: Float, range: Range<String.Index>) -> AttributedString {
    let a = TextAttribute(range: range, fontName: name, fontSize: size)
    return AttributedString(string: string, attributes: attributes + [a])
  }

  public func withStroke(width: Float, color: Color, range: Range<String.Index>)
    -> AttributedString
  {
    let a = TextAttribute(range: range, stroke: TextStroke(width: width, color: color))
    return AttributedString(string: string, attributes: attributes + [a])
  }

  public func withShadow(
    width: Float, offset: Point, color: Color, range: Range<String.Index>
  ) -> AttributedString {
    let a = TextAttribute(range: range, shadow: TextShadow(width: width, offset: offset, color: color))
    return AttributedString(string: string, attributes: attributes + [a])
  }

  public func withColor(_ color: Color, substring: String) -> AttributedString {
    guard let r = string.range(of: substring) else { return self }
    return withColor(color, range: r)
  }
}

// MARK: - Queries
public struct ResolvedTextAttributes: Equatable {
  public var color: Color
  public var fontName: String?
  public var fontSize: Float?
  public var stroke: TextStroke?
  public var shadow: TextShadow?
}

extension AttributedString {
  /// Resolve attributes at a character index with defaults if unspecified.
  public func attributes(at index: String.Index, defaultColor: Color = .white)
    -> ResolvedTextAttributes?
  {
    guard index >= string.startIndex && index < string.endIndex else { return nil }

    var resolved = ResolvedTextAttributes(color: defaultColor, fontName: nil, fontSize: nil, stroke: nil, shadow: nil)

    for a in attributes where a.range.contains(index) {
      if let c = a.color { resolved.color = c }
      if let n = a.fontName { resolved.fontName = n }
      if let s = a.fontSize { resolved.fontSize = s }
      if let st = a.stroke { resolved.stroke = st }
      if let sh = a.shadow { resolved.shadow = sh }
    }
    return resolved
  }
}

// MARK: - Drawing Extensions

/// Text anchor options for positioning text
public enum TextAnchor {
  case topLeft
  case bottomLeft
  case baselineLeft
}

extension AttributedString {
  /// Draws the attributed string at the specified point.
  /// - Parameters:
  ///   - point: The point to draw the text at.
  ///   - defaultStyle: The default text style to use for unformatted text.
  ///   - wrapWidth: Optional width to wrap text at.
  ///   - anchor: The anchor point for positioning.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    at point: Point,
    defaultStyle: TextStyle,
    wrapWidth: Float? = nil,
    anchor: TextAnchor = .topLeft,
    context: GraphicsContext? = nil
  ) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }

    ctx.renderer.drawText(
      self,
      at: point,
      defaultStyle: defaultStyle,
      wrapWidth: wrapWidth,
      anchor: anchor
    )
  }

  /// Draws the attributed string within the specified rectangle.
  /// - Parameters:
  ///   - rect: The rectangle to draw the text within.
  ///   - defaultStyle: The default text style to use for unformatted text.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    in rect: Rect,
    defaultStyle: TextStyle,
    context: GraphicsContext? = nil
  ) {
    draw(at: rect.origin, defaultStyle: defaultStyle, context: context)
  }
}

extension String {
  /// Draws the string at the specified point with the given style.
  /// - Parameters:
  ///   - point: The point to draw the text at.
  ///   - style: The text style to apply.
  ///   - wrapWidth: Optional width to wrap text at.
  ///   - anchor: The anchor point for positioning.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    at point: Point,
    style: TextStyle,
    wrapWidth: Float? = nil,
    anchor: TextAnchor = .topLeft,
    context: GraphicsContext? = nil
  ) {
    let attributed = AttributedString(
      string: self,
      attributes: [
        TextAttribute(
          range: startIndex..<endIndex,
          color: style.color,
          fontName: style.fontName,
          fontSize: style.fontSize
        )
      ])
    attributed.draw(at: point, defaultStyle: style, wrapWidth: wrapWidth, anchor: anchor, context: context)
  }

  /// Draws the string within the specified rectangle with the given style.
  /// - Parameters:
  ///   - rect: The rectangle to draw the text within.
  ///   - style: The text style to apply.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    in rect: Rect,
    style: TextStyle,
    context: GraphicsContext? = nil
  ) {
    draw(at: rect.origin, style: style, context: context)
  }
}
