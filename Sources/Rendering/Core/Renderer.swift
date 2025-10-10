/// A protocol defining the interface for rendering operations.
public protocol Renderer {
  // MARK: - Frame lifecycle

  /// Begins a new rendering frame with the specified viewport size and scale.
  /// - Parameters:
  ///   - viewportSize: The size of the viewport in points.
  ///   - scale: The scale factor for coordinate transformations.
  func beginFrame(viewportSize: Size, scale: Float)

  /// Ends the current rendering frame and presents the results.
  func endFrame()

  // MARK: - State

  /// Sets the clipping rectangle for subsequent drawing operations.
  /// - Parameter rect: The rectangle to clip drawing to, or `nil` to disable clipping.
  func setClipRect(_ rect: Rect?)

  /// Sets whether to render in wireframe mode.
  /// - Parameter enabled: `true` for wireframe rendering, `false` for filled polygons.
  func setWireframeMode(_ enabled: Bool)

  /// Sets the clear color for the next frame.
  /// - Parameter color: The color to clear the screen with.
  func setClearColor(_ color: Color)

  // MARK: - Primitives

  /// Draws an image with the specified texture ID in the given rectangle.
  /// - Parameters:
  ///   - textureID: The ID of the texture to draw.
  ///   - rect: The rectangle to draw the image in.
  ///   - tint: Optional color tint to apply to the image.
  func drawImage(textureID: UInt64, in rect: Rect, tint: Color?)

  /// Draws a region of an image with the specified texture ID and UV coordinates.
  /// - Parameters:
  ///   - textureID: The ID of the texture to draw.
  ///   - rect: The rectangle to draw the image region in.
  ///   - uv: The UV coordinates defining the region to draw (normalized 0-1).
  ///   - tint: Optional color tint to apply to the image.
  func drawImageRegion(textureID: UInt64, in rect: Rect, uv: Rect, tint: Color?)

  // MARK: - Text

  /// Draws attributed text at the specified location.
  /// - Parameters:
  ///   - attributedString: The attributed string to draw.
  ///   - origin: The point to draw the text at.
  ///   - defaultStyle: The default text style to use for unformatted text.
  ///   - wrapWidth: Optional width to wrap text at.
  ///   - anchor: The anchor point for positioning.
  ///   - alignment: Text alignment within the wrap width.
  func drawText(
    _ attributedString: AttributedString,
    at origin: Point,
    defaultStyle: TextStyle,
    wrapWidth: Float?,
    anchor: TextAnchor,
    alignment: TextAlignment
  )

  // MARK: - Paths

  /// Draws a filled path using the specified color.
  /// - Parameters:
  ///   - path: The bezier path to draw.
  ///   - color: The color to fill the path with.
  func drawPath(_ path: BezierPath, color: Color)

  /// Draws a stroked path with the specified color and line width.
  /// - Parameters:
  ///   - path: The bezier path to draw.
  ///   - color: The color to stroke the path with.
  ///   - lineWidth: The width of the stroke.
  func drawStroke(_ path: BezierPath, color: Color, lineWidth: Float)
}
