/// A 2D point with floating-point coordinates.
public struct Point: Equatable, Hashable, Sendable {
  /// The x-coordinate of the point.
  public var x: Float
  /// The y-coordinate of the point.
  public var y: Float

  /// Creates a new point with the specified coordinates.
  /// - Parameters:
  ///   - x: The x-coordinate.
  ///   - y: The y-coordinate.
  public init(_ x: Float, _ y: Float) {
    self.x = x
    self.y = y
  }

  /// A point at the origin (0, 0).
  public static let zero = Point(0, 0)
}

/// A 2D size with floating-point dimensions.
public struct Size: Equatable, Hashable, Sendable {
  /// The width of the size.
  public var width: Float
  /// The height of the size.
  public var height: Float

  /// Creates a new size with the specified dimensions.
  /// - Parameters:
  ///   - width: The width.
  ///   - height: The height.
  public init(_ width: Float, _ height: Float) {
    self.width = width
    self.height = height
  }

  /// A size with zero width and height.
  public static let zero = Size(0, 0)
}

/// A 2D rectangle with floating-point coordinates and dimensions.
public struct Rect: Equatable, Hashable, Sendable {
  /// The origin point of the rectangle.
  public var origin: Point
  /// The size of the rectangle.
  public var size: Size

  /// Creates a new rectangle with the specified origin and size.
  /// - Parameters:
  ///   - origin: The origin point of the rectangle.
  ///   - size: The size of the rectangle.
  public init(origin: Point, size: Size) {
    self.origin = origin
    self.size = size
  }

  /// Creates a new rectangle with the specified coordinates and dimensions.
  /// - Parameters:
  ///   - x: The x-coordinate of the origin.
  ///   - y: The y-coordinate of the origin.
  ///   - width: The width of the rectangle.
  ///   - height: The height of the rectangle.
  public init(x: Float, y: Float, width: Float, height: Float) {
    self.origin = Point(x, y)
    self.size = Size(width, height)
  }

  /// A rectangle at the origin with zero size.
  public static let zero = Rect(origin: .zero, size: .zero)
}

/// Edge insets for rectangles, specifying how much to inset each edge.
public struct EdgeInsets: Equatable, Hashable, Sendable {
  /// The inset for the top edge.
  public var top: Float
  /// The inset for the left edge.
  public var left: Float
  /// The inset for the right edge.
  public var right: Float
  /// The inset for the bottom edge.
  public var bottom: Float

  /// Creates new edge insets with the specified values.
  /// - Parameters:
  ///   - top: The inset for the top edge.
  ///   - left: The inset for the left edge.
  ///   - bottom: The inset for the bottom edge.
  ///   - right: The inset for the right edge.
  public init(top: Float, left: Float, bottom: Float, right: Float) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }

  /// Creates edge insets with the same value for all edges.
  /// - Parameter value: The inset value for all edges.
  public init(_ value: Float) {
    self.top = value
    self.left = value
    self.right = value
    self.bottom = value
  }

  /// Edge insets with zero values for all edges.
  public static let zero = EdgeInsets(0)
}

// MARK: - Geometry Operations

extension Rect {
  /// Returns a rectangle that is inset by the specified edge insets.
  /// - Parameter insets: The edge insets to apply.
  /// - Returns: A new rectangle inset by the specified amounts.
  public func inset(by insets: EdgeInsets) -> Rect {
    return Rect(
      x: origin.x + insets.left,
      y: origin.y + insets.top,
      width: size.width - insets.left - insets.right,
      height: size.height - insets.top - insets.bottom
    )
  }

  /// Returns a rectangle that is inset by the specified amounts on all sides.
  /// - Parameters:
  ///   - dx: The horizontal inset amount.
  ///   - dy: The vertical inset amount.
  /// - Returns: A new rectangle inset by the specified amounts.
  public func insetBy(dx: Float, dy: Float) -> Rect {
    return inset(by: EdgeInsets(top: dy, left: dx, bottom: dy, right: dx))
  }

  /// Returns a rectangle that is offset by the specified amounts.
  /// - Parameters:
  ///   - dx: The horizontal offset amount.
  ///   - dy: The vertical offset amount.
  /// - Returns: A new rectangle offset by the specified amounts.
  public func offsetBy(dx: Float, dy: Float) -> Rect {
    return Rect(
      x: origin.x + dx,
      y: origin.y + dy,
      width: size.width,
      height: size.height
    )
  }
}

// MARK: - Drawing Operations

extension Rect {
  /// Fills this rectangle in the current graphics context with the specified color.
  /// - Parameter color: The color to fill the rectangle with.
  public func fill(with color: Color) {
    guard let context = GraphicsContext.current else { return }

    var path = BezierPath()
    path.addRect(self)
    context.drawPath(path, color: color)
  }

  /// Draws a frame around the inside of this rectangle in the current graphics context with the specified color and line width.
  /// - Parameters:
  ///   - color: The color to stroke the frame with.
  ///   - lineWidth: The width of the frame stroke.
  public func frame(with color: Color, lineWidth: Float = 1.0) {
    guard let context = GraphicsContext.current else { return }

    // Create a path for the frame (inside stroke)
    var path = BezierPath()
    let insetRect = insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
    path.addRect(insetRect)

    context.drawStroke(path, color: color, lineWidth: lineWidth)
  }
}
