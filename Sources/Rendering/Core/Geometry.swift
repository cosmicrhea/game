/// A 2D point with floating-point coordinates.
public struct Point: Equatable, Hashable {
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
}

/// A 2D size with floating-point dimensions.
public struct Size: Equatable, Hashable {
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
}

/// A 2D rectangle with floating-point coordinates and dimensions.
public struct Rect: Equatable, Hashable {
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
}
