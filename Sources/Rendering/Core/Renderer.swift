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

  // MARK: - Text (stub for now)

  /// Draws glyphs from a font atlas.
  /// - Parameters:
  ///   - atlasID: The ID of the font atlas texture.
  ///   - vertices: Buffer of vertex data for the glyphs.
  ///   - color: The color to apply to the glyphs.
  func drawGlyphs(atlasID: UInt64, vertices: UnsafeBufferPointer<Float>, color: Color)

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
