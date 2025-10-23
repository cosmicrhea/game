/// Text alignment options
public enum TextAlignment: Sendable {
  case left
  case center
  case right
}

/// Style configuration for text rendering.
public struct TextStyle: Sendable {
  /// Name of the font to use.
  public var fontName: String
  /// Size of the font in points.
  public var fontSize: Float
  /// Color of the text.
  public var color: Color
  /// Text alignment.
  public var alignment: TextAlignment
  /// Line height multiplier. If nil, uses font's natural line height.
  public var lineHeight: Float?

  // Stroke properties
  /// Width of the stroke in points. If 0, no stroke is applied.
  public var strokeWidth: Float
  /// Color of the stroke.
  public var strokeColor: Color

  // Shadow properties
  /// Blur radius of the shadow in points. If 0, no shadow is applied.
  public var shadowWidth: Float
  /// Offset of the shadow from the text.
  public var shadowOffset: Point
  /// Color of the shadow.
  public var shadowColor: Color

  /// Layout features (e.g., monospaced digits). Applied at layout-time.
  public var monospaceDigits: Bool = false

  /// Creates a new text style with the specified properties.
  /// - Parameters:
  ///   - fontName: Name of the font to use.
  ///   - fontSize: Size of the font in points.
  ///   - color: Color of the text.
  ///   - alignment: Text alignment.
  ///   - lineHeight: Line height multiplier. If nil, uses font's natural line height.
  ///   - strokeWidth: Width of the stroke in points. If 0, no stroke is applied.
  ///   - strokeColor: Color of the stroke.
  ///   - shadowWidth: Blur radius of the shadow in points. If 0, no shadow is applied.
  ///   - shadowOffset: Offset of the shadow from the text.
  ///   - shadowColor: Color of the shadow.
  public init(
    fontName: String,
    fontSize: Float,
    color: Color,
    alignment: TextAlignment = .left,
    lineHeight: Float? = nil,
    strokeWidth: Float = 0,
    strokeColor: Color = .clear,
    shadowWidth: Float = 0,
    shadowOffset: Point = Point(0, 0),
    shadowColor: Color = .clear,
    monospaceDigits: Bool = false
  ) {
    self.fontName = fontName
    self.fontSize = fontSize
    self.color = color
    self.alignment = alignment
    self.lineHeight = lineHeight
    self.strokeWidth = strokeWidth
    self.strokeColor = strokeColor
    self.shadowWidth = shadowWidth
    self.shadowOffset = shadowOffset
    self.shadowColor = shadowColor
    self.monospaceDigits = monospaceDigits
  }

  /// Creates a new text style with a different alignment.
  /// - Parameter alignment: The new alignment to use.
  /// - Returns: A new TextStyle with the specified alignment.
  public func withAlignment(_ alignment: TextAlignment) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.strokeWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different color.
  /// - Parameter color: The new color to use.
  /// - Returns: A new TextStyle with the specified color.
  public func withColor(_ color: Color) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different font size.
  /// - Parameter fontSize: The new font size to use.
  /// - Returns: A new TextStyle with the specified font size.
  public func withFontSize(_ fontSize: Float) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different font name.
  /// - Parameter fontName: The new font name to use.
  /// - Returns: A new TextStyle with the specified font name.
  public func withFontName(_ fontName: String) -> TextStyle {
    return TextStyle(
      fontName: fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with different stroke properties.
  /// - Parameters:
  ///   - strokeWidth: The new stroke width to use.
  ///   - strokeColor: The new stroke color to use.
  /// - Returns: A new TextStyle with the specified stroke properties.
  public func withStroke(width strokeWidth: Float, color strokeColor: Color) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: strokeWidth,
      strokeColor: strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with different shadow properties.
  /// - Parameters:
  ///   - shadowWidth: The new shadow width to use.
  ///   - shadowOffset: The new shadow offset to use.
  ///   - shadowColor: The new shadow color to use.
  /// - Returns: A new TextStyle with the specified shadow properties.
  public func withShadow(width shadowWidth: Float, offset shadowOffset: Point, color shadowColor: Color) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: shadowWidth,
      shadowOffset: shadowOffset,
      shadowColor: shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different line height.
  /// - Parameter lineHeight: The new line height multiplier to use.
  /// - Returns: A new TextStyle with the specified line height.
  public func withLineHeight(_ lineHeight: Float?) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different stroke color.
  /// - Parameter strokeColor: The new stroke color to use.
  /// - Returns: A new TextStyle with the specified stroke color.
  public func withStrokeColor(_ strokeColor: Color) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with a different shadow color.
  /// - Parameter shadowColor: The new shadow color to use.
  /// - Returns: A new TextStyle with the specified shadow color.
  public func withShadowColor(_ shadowColor: Color) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: shadowColor,
      monospaceDigits: self.monospaceDigits
    )
  }

  /// Creates a new text style with monospaced digits toggled.
  /// - Parameter enabled: Whether to enable fixed-width advance for '0'..'9'.
  /// - Returns: A new TextStyle with the specified monospace-digits flag.
  public func withMonospacedDigits(_ enabled: Bool) -> TextStyle {
    return TextStyle(
      fontName: self.fontName,
      fontSize: self.fontSize,
      color: self.color,
      alignment: self.alignment,
      lineHeight: self.lineHeight,
      strokeWidth: self.strokeWidth,
      strokeColor: self.strokeColor,
      shadowWidth: self.shadowWidth,
      shadowOffset: self.shadowOffset,
      shadowColor: self.shadowColor,
      monospaceDigits: enabled
    )
  }
}

/// Stroke configuration for text rendering.
public struct TextStroke: Equatable, Sendable {
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
public struct TextShadow: Equatable, Sendable {
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

// TextAnchor has been replaced with the centralized Alignment enum in Geometry.swift

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
    anchor: AnchorPoint = .topLeft,
    context: GraphicsContext? = nil
  ) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }

    ctx.renderer.drawText(
      self,
      at: point,
      defaultStyle: defaultStyle,
      wrapWidth: wrapWidth,
      anchor: anchor,
      textAlignment: defaultStyle.alignment
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
    anchor: AnchorPoint = .topLeft,
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

// MARK: - Measurement Functions

extension AttributedString {
  /// Returns the size necessary to draw the string.
  /// - Parameters:
  ///   - defaultStyle: The default text style to use for measurement.
  ///   - wrapWidth: Optional width constraint for text wrapping.
  /// - Returns: The size required to draw the string.
  public func size(defaultStyle: TextStyle, wrapWidth: Float? = nil) -> Size {
    return boundingRect(defaultStyle: defaultStyle, wrapWidth: wrapWidth).size
  }

  /// Returns the bounding rectangle necessary to draw the string.
  /// - Parameters:
  ///   - defaultStyle: The default text style to use for measurement.
  ///   - wrapWidth: Optional width constraint for text wrapping.
  /// - Returns: The bounding rectangle required to draw the string.
  public func boundingRect(defaultStyle: TextStyle, wrapWidth: Float? = nil) -> Rect {
    // Create font and layout for measurement
    let features = Font.Features(monospaceDigits: defaultStyle.monospaceDigits)
    guard let font = Font(fontName: defaultStyle.fontName, pixelHeight: defaultStyle.fontSize, features: features)
    else {
      return Rect(origin: Point(0, 0), size: Size(0, 0))
    }

    let layout = TextLayout(font: font, scale: 1.0)

    // Layout the text using TextStyle (respects lineHeight)
    let layoutResult = layout.layout(
      string,
      style: defaultStyle,
      wrapWidth: wrapWidth
    )

    return Rect(
      origin: Point(0, 0),
      size: Size(layoutResult.totalWidth, layoutResult.totalHeight)
    )
  }
}

extension String {
  /// Returns the bounding box size the receiver occupies when drawn with the given attributes.
  /// - Parameters:
  ///   - style: The text style to use for measurement.
  ///   - wrapWidth: Optional width constraint for text wrapping.
  /// - Returns: The size required to draw the string.
  public func size(with style: TextStyle, wrapWidth: Float? = nil) -> Size {
    return AttributedString(string: self).size(defaultStyle: style, wrapWidth: wrapWidth)
  }

  /// Calculates and returns the bounding rect for the receiver drawn using the given options.
  /// - Parameters:
  ///   - style: The text style to use for measurement.
  ///   - wrapWidth: Optional width constraint for text wrapping.
  /// - Returns: The bounding rectangle required to draw the string.
  public func boundingRect(with style: TextStyle, wrapWidth: Float? = nil) -> Rect {
    return AttributedString(string: self).boundingRect(defaultStyle: style, wrapWidth: wrapWidth)
  }
}
