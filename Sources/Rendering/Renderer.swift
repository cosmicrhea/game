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

  // MARK: - UI Context

  /// Execute a block with UI rendering state (no depth testing, blending enabled)
  /// - Parameter block: The block to execute with UI context
  /// - Returns: The result of the block
  func withUIContext<T>(_ block: () throws -> T) rethrows -> T

  // MARK: - Framebuffer Objects (FBO)

  /// Creates a framebuffer object for off-screen rendering
  /// - Parameters:
  ///   - size: The size of the framebuffer
  ///   - scale: The scale factor for the framebuffer
  /// - Returns: A framebuffer ID that can be used for rendering
  func createFramebuffer(size: Size, scale: Float) -> UInt64

  /// Destroys a framebuffer object
  /// - Parameter framebufferID: The ID of the framebuffer to destroy
  func destroyFramebuffer(_ framebufferID: UInt64)

  /// Begins rendering to a framebuffer
  /// - Parameter framebufferID: The ID of the framebuffer to render to
  func beginFramebuffer(_ framebufferID: UInt64)

  /// Ends rendering to a framebuffer and returns to the main framebuffer
  func endFramebuffer()

  /// Draws a framebuffer as a texture with optional transform and alpha
  /// - Parameters:
  ///   - framebufferID: The ID of the framebuffer to draw
  ///   - rect: The rectangle to draw the framebuffer in
  ///   - transform: Optional transformation matrix (translation, rotation, scale)
  ///   - alpha: Alpha value for blending (0.0 = transparent, 1.0 = opaque)
  func drawFramebuffer(
    _ framebufferID: UInt64,
    in rect: Rect,
    transform: Transform2D?,
    alpha: Float
  )
}

// MARK: - Transform2D

/// A 2D transformation matrix for framebuffer rendering
public struct Transform2D {
  public let translation: Point
  public let rotation: Float  // in radians
  public let scale: Point

  public init(translation: Point = Point(0, 0), rotation: Float = 0, scale: Point = Point(1, 1)) {
    self.translation = translation
    self.rotation = rotation
    self.scale = scale
  }
}
