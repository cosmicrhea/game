/// A graphics context that manages rendering state and provides drawing operations.
public final class GraphicsContext {
  /// The current graphics context for implicit drawing operations.
  nonisolated(unsafe) public static var current: GraphicsContext?

  private var clipStack: [Rect?] = [nil]

  /// The underlying renderer used for drawing operations.
  public let renderer: Renderer
  /// The scale factor for coordinate transformations.
  public let scale: Float
  /// Whether the coordinate system is flipped (origin at top-left instead of bottom-left).
  public let isFlipped: Bool

  /// The current viewport size in points.
  public var size: Size {
    return renderer.viewportSize
  }

  /// Shortcut for viewport size - returns (0,0) if no context
  public static var viewportSize: Size {
    return current?.size ?? Size(0, 0)
  }

  /// Creates a new graphics context with the specified renderer and scale.
  /// - Parameters:
  ///   - renderer: The renderer to use for drawing operations.
  ///   - scale: The scale factor for coordinate transformations.
  ///   - isFlipped: Whether the coordinate system is flipped (origin at top-left).
  public init(renderer: Renderer, scale: Float = 1, isFlipped: Bool = false) {
    self.renderer = renderer
    self.scale = scale
    self.isFlipped = isFlipped
  }

  /// Temporarily sets the current graphics context and executes the provided closure.
  /// - Parameters:
  ///   - context: The context to set as current.
  ///   - body: The closure to execute with the context set.
  /// - Returns: The result of the closure execution.
  @discardableResult
  public static func withContext<T>(_ context: GraphicsContext, _ body: () throws -> T) rethrows -> T {
    let previous = GraphicsContext.current
    GraphicsContext.current = context
    defer { GraphicsContext.current = previous }
    return try body()
  }

  // State stack
  /// Saves the current graphics state to the stack.
  public func save() { clipStack.append(clipStack.last ?? nil) }

  /// Restores the previous graphics state from the stack.
  public func restore() {
    _ = clipStack.popLast()
    renderer.setClipRect(clipStack.last ?? nil)
  }

  /// Sets the clipping rectangle for subsequent drawing operations.
  /// - Parameter rect: The rectangle to clip drawing to, or `nil` to disable clipping.
  public func clip(to rect: Rect) {
    clipStack[clipStack.count - 1] = rect
    renderer.setClipRect(rect)
  }

  // MARK: - Path Drawing

  /// Draws a filled path using the specified color.
  /// - Parameters:
  ///   - path: The bezier path to draw.
  ///   - color: The color to fill the path with.
  public func drawPath(_ path: BezierPath, color: Color) {
    renderer.drawPath(path, color: color)
  }

  /// Draws a stroked path with the specified color and line width.
  /// - Parameters:
  ///   - path: The bezier path to draw.
  ///   - color: The color to stroke the path with.
  ///   - lineWidth: The width of the stroke.
  public func drawStroke(_ path: BezierPath, color: Color, lineWidth: Float) {
    renderer.drawStroke(path, color: color, lineWidth: lineWidth)
  }

  /// Draws a filled rounded rectangle.
  /// - Parameters:
  ///   - rect: The rectangle to draw.
  ///   - cornerRadius: The radius of the rounded corners.
  ///   - color: The color to fill the rectangle with.
  public func drawRoundedRect(_ rect: Rect, cornerRadius: Float, color: Color) {
    var path = BezierPath()
    path.addRoundedRect(rect, cornerRadius: cornerRadius)
    drawPath(path, color: color)
  }

  /// Draws a stroked rounded rectangle.
  /// - Parameters:
  ///   - rect: The rectangle to draw.
  ///   - cornerRadius: The radius of the rounded corners.
  ///   - color: The color to stroke the rectangle with.
  ///   - lineWidth: The width of the stroke.
  public func drawStrokeRoundedRect(_ rect: Rect, cornerRadius: Float, color: Color, lineWidth: Float) {
    var path = BezierPath()
    path.addRoundedRect(rect, cornerRadius: cornerRadius)
    drawStroke(path, color: color, lineWidth: lineWidth)
  }

  // MARK: - Coordinate System Helpers

  /// Flips a Y coordinate if the context is flipped.
  /// - Parameter y: The Y coordinate to potentially flip.
  /// - Returns: The flipped Y coordinate if needed.
  public func flipY(_ y: Float) -> Float {
    return isFlipped ? size.height - y : y
  }

  /// Flips a point if the context is flipped.
  /// - Parameter point: The point to potentially flip.
  /// - Returns: The flipped point if needed.
  public func flipPoint(_ point: Point) -> Point {
    return isFlipped ? Point(point.x, size.height - point.y) : point
  }

  /// Flips a rectangle if the context is flipped.
  /// - Parameter rect: The rectangle to potentially flip.
  /// - Returns: The flipped rectangle if needed.
  public func flipRect(_ rect: Rect) -> Rect {
    return isFlipped
      ? Rect(x: rect.origin.x, y: size.height - rect.maxY, width: rect.size.width, height: rect.size.height) : rect
  }
}
