import Foundation

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

// MARK: - Additional Rect Methods

extension Rect {
  /// Returns whether this rectangle contains the specified point.
  /// - Parameter point: The point to test.
  /// - Returns: `true` if the point is inside the rectangle, `false` otherwise.
  public func contains(_ point: Point) -> Bool {
    return point.x >= origin.x && point.x <= origin.x + size.width && point.y >= origin.y
      && point.y <= origin.y + size.height
  }

  /// Returns whether this rectangle contains the specified rectangle.
  /// - Parameter rect: The rectangle to test.
  /// - Returns: `true` if the rectangle is completely inside this rectangle, `false` otherwise.
  public func contains(_ rect: Rect) -> Bool {
    return rect.origin.x >= origin.x && rect.origin.y >= origin.y
      && rect.origin.x + rect.size.width <= origin.x + size.width
      && rect.origin.y + rect.size.height <= origin.y + size.height
  }

  /// Divides this rectangle at the specified distance from the specified edge.
  /// - Parameters:
  ///   - distance: The distance from the edge to divide at.
  ///   - edge: The edge to divide from.
  /// - Returns: A tuple containing the slice (the divided portion) and the remainder.
  public func divided(atDistance distance: Float, from edge: CGRectEdge) -> (slice: Rect, remainder: Rect) {
    switch edge {
    case .minXEdge:
      let slice = Rect(x: origin.x, y: origin.y, width: distance, height: size.height)
      let remainder = Rect(x: origin.x + distance, y: origin.y, width: size.width - distance, height: size.height)
      return (slice, remainder)
    case .maxXEdge:
      let slice = Rect(x: origin.x + size.width - distance, y: origin.y, width: distance, height: size.height)
      let remainder = Rect(x: origin.x, y: origin.y, width: size.width - distance, height: size.height)
      return (slice, remainder)
    case .minYEdge:
      let slice = Rect(x: origin.x, y: origin.y, width: size.width, height: distance)
      let remainder = Rect(x: origin.x, y: origin.y + distance, width: size.width, height: size.height - distance)
      return (slice, remainder)
    case .maxYEdge:
      let slice = Rect(x: origin.x, y: origin.y + size.height - distance, width: size.width, height: distance)
      let remainder = Rect(x: origin.x, y: origin.y, width: size.width, height: size.height - distance)
      return (slice, remainder)
    }
  }

  /// Returns whether this rectangle is equal to the specified rectangle.
  /// - Parameter rect: The rectangle to compare with.
  /// - Returns: `true` if the rectangles are equal, `false` otherwise.
  public func equalTo(_ rect: Rect) -> Bool {
    return self == rect
  }

  /// Returns the intersection of this rectangle with the specified rectangle.
  /// - Parameter rect: The rectangle to intersect with.
  /// - Returns: The intersection rectangle, or a zero rectangle if they don't intersect.
  public func intersection(_ rect: Rect) -> Rect {
    let left = max(origin.x, rect.origin.x)
    let top = max(origin.y, rect.origin.y)
    let right = min(origin.x + size.width, rect.origin.x + rect.size.width)
    let bottom = min(origin.y + size.height, rect.origin.y + rect.size.height)

    if left >= right || top >= bottom {
      return .zero
    }

    return Rect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// Returns whether this rectangle intersects with the specified rectangle.
  /// - Parameter rect: The rectangle to test intersection with.
  /// - Returns: `true` if the rectangles intersect, `false` otherwise.
  public func intersects(_ rect: Rect) -> Bool {
    return
      !(origin.x + size.width <= rect.origin.x || rect.origin.x + rect.size.width <= origin.x
      || origin.y + size.height <= rect.origin.y || rect.origin.y + rect.size.height <= origin.y)
  }

  /// Returns the union of this rectangle with the specified rectangle.
  /// - Parameter rect: The rectangle to union with.
  /// - Returns: The smallest rectangle that contains both rectangles.
  public func union(_ rect: Rect) -> Rect {
    let left = min(origin.x, rect.origin.x)
    let top = min(origin.y, rect.origin.y)
    let right = max(origin.x + size.width, rect.origin.x + rect.size.width)
    let bottom = max(origin.y + size.height, rect.origin.y + rect.size.height)

    return Rect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// Returns a rectangle with integral coordinates (rounded to nearest integers).
  public var integral: Rect {
    return Rect(
      x: floor(origin.x),
      y: floor(origin.y),
      width: ceil(origin.x + size.width) - floor(origin.x),
      height: ceil(origin.y + size.height) - floor(origin.y)
    )
  }

  /// Returns whether this rectangle is empty (has zero or negative width or height).
  public var isEmpty: Bool {
    return size.width <= 0 || size.height <= 0
  }
}

/// Edge enumeration for rectangle division operations.
public enum CGRectEdge {
  case minXEdge
  case minYEdge
  case maxXEdge
  case maxYEdge
}
