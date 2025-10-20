/// A path that consists of straight and curved line segments.
public struct BezierPath {
  /// A single path element (move, line, curve, etc.)
  public enum Element {
    case moveTo(Point)
    case lineTo(Point)
    case quadCurveTo(Point, control: Point)
    case curveTo(Point, control1: Point, control2: Point)
    case closePath
  }

  private var elements: [Element] = []
  private var currentPoint: Point = Point(0, 0)

  public init() {}

  /// Moves the current point to the specified location.
  /// - Parameter point: The new current point.
  public mutating func move(to point: Point) {
    elements.append(.moveTo(point))
    currentPoint = point
  }

  /// Adds a line from the current point to the specified point.
  /// - Parameter point: The end point of the line.
  public mutating func addLine(to point: Point) {
    elements.append(.lineTo(point))
    currentPoint = point
  }

  /// Adds a quadratic curve from the current point to the specified point.
  /// - Parameters:
  ///   - point: The end point of the curve.
  ///   - control: The control point of the curve.
  public mutating func addQuadCurve(to point: Point, control: Point) {
    elements.append(.quadCurveTo(point, control: control))
    currentPoint = point
  }

  /// Adds a cubic curve from the current point to the specified point.
  /// - Parameters:
  ///   - point: The end point of the curve.
  ///   - control1: The first control point of the curve.
  ///   - control2: The second control point of the curve.
  public mutating func addCurve(to point: Point, control1: Point, control2: Point) {
    elements.append(.curveTo(point, control1: control1, control2: control2))
    currentPoint = point
  }

  /// Closes the current subpath by adding a line to the starting point.
  public mutating func closePath() {
    elements.append(.closePath)
  }

  /// Returns the path elements for processing.
  public var pathElements: [Element] {
    return elements
  }

  /// Adds a rectangle to the path.
  /// - Parameter rect: The rectangle to add.
  public mutating func addRect(_ rect: Rect) {
    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    // Start from top-left corner
    move(to: Point(x, y))

    // Top edge
    addLine(to: Point(x + w, y))

    // Right edge
    addLine(to: Point(x + w, y + h))

    // Bottom edge
    addLine(to: Point(x, y + h))

    // Left edge (back to start)
    addLine(to: Point(x, y))

    closePath()
  }

  /// Adds a rounded rectangle to the path.
  /// - Parameters:
  ///   - rect: The rectangle to add.
  ///   - cornerRadius: The radius of the rounded corners.
  public mutating func addRoundedRect(_ rect: Rect, cornerRadius: Float) {
    let radius = min(cornerRadius, min(rect.size.width, rect.size.height) / 2)
    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    // Start from top-left corner (after rounding)
    move(to: Point(x + radius, y))

    // Top edge
    addLine(to: Point(x + w - radius, y))

    // Top-right corner
    addQuadCurve(
      to: Point(x + w, y + radius),
      control: Point(x + w, y)
    )

    // Right edge
    addLine(to: Point(x + w, y + h - radius))

    // Bottom-right corner
    addQuadCurve(
      to: Point(x + w - radius, y + h),
      control: Point(x + w, y + h)
    )

    // Bottom edge
    addLine(to: Point(x + radius, y + h))

    // Bottom-left corner
    addQuadCurve(
      to: Point(x, y + h - radius),
      control: Point(x, y + h)
    )

    // Left edge
    addLine(to: Point(x, y + radius))

    // Top-left corner
    addQuadCurve(
      to: Point(x + radius, y),
      control: Point(x, y)
    )

    closePath()
  }

  /// Tessellates the path into triangles for rendering.
  /// - Parameter tolerance: The maximum distance between the curve and its approximation.
  /// - Returns: Arrays of vertices and indices for triangle rendering.
  public func tessellate(tolerance: Float = 1.0) -> (vertices: [Float], indices: [UInt32]) {
    var vertices: [Float] = []
    var indices: [UInt32] = []
    var currentIndex: UInt32 = 0
    var subpathStart: UInt32 = 0

    for element in elements {
      switch element {
      case .moveTo(let point):
        vertices.append(contentsOf: [point.x, point.y])
        subpathStart = currentIndex
        currentIndex += 1

      case .lineTo(let point):
        vertices.append(contentsOf: [point.x, point.y])
        currentIndex += 1

      case .quadCurveTo(let endPoint, let control):
        let startPoint = Point(vertices[Int(currentIndex - 1) * 2], vertices[Int(currentIndex - 1) * 2 + 1])
        let tessellated = tessellateQuadCurve(from: startPoint, to: endPoint, control: control, tolerance: tolerance)

        for point in tessellated.dropFirst() {  // Skip first point as it's already added
          vertices.append(contentsOf: [point.x, point.y])
          currentIndex += 1
        }

      case .curveTo(let endPoint, let control1, let control2):
        let startPoint = Point(vertices[Int(currentIndex - 1) * 2], vertices[Int(currentIndex - 1) * 2 + 1])
        let tessellated = tessellateCubicCurve(
          from: startPoint, to: endPoint, control1: control1, control2: control2, tolerance: tolerance)

        for point in tessellated.dropFirst() {  // Skip first point as it's already added
          vertices.append(contentsOf: [point.x, point.y])
          currentIndex += 1
        }

      case .closePath:
        if currentIndex > subpathStart + 2 {
          // Create a fan of triangles from the first vertex
          for i in (subpathStart + 1)..<(currentIndex - 1) {
            indices.append(contentsOf: [subpathStart, i, i + 1])
          }
        }
      }
    }

    return (vertices, indices)
  }

  // MARK: - Private Tessellation Helpers

  private func tessellateQuadCurve(from start: Point, to end: Point, control: Point, tolerance: Float) -> [Point] {
    var points: [Point] = [start]

    func subdivide(_ t1: Float, _ t2: Float, _ p1: Point, _ p2: Point, _ p3: Point) {
      let t = (t1 + t2) / 2
      let midPoint = evaluateQuadCurve(t: t, start: start, control: control, end: end)
      let flatness = calculateQuadFlatness(p1: p1, p2: p2, p3: p3)

      if flatness <= tolerance {
        points.append(midPoint)
      } else {
        subdivide(t1, t, p1, midPoint, p2)
        subdivide(t, t2, p2, midPoint, p3)
      }
    }

    subdivide(0, 1, start, control, end)
    points.append(end)
    return points
  }

  private func tessellateCubicCurve(
    from start: Point, to end: Point, control1: Point, control2: Point, tolerance: Float
  ) -> [Point] {
    var points: [Point] = [start]

    func subdivide(_ t1: Float, _ t2: Float, _ p1: Point, _ p2: Point, _ p3: Point, _ p4: Point) {
      let t = (t1 + t2) / 2
      let midPoint = evaluateCubicCurve(t: t, start: start, control1: control1, control2: control2, end: end)
      let flatness = calculateCubicFlatness(p1: p1, p2: p2, p3: p3, p4: p4)

      if flatness <= tolerance {
        points.append(midPoint)
      } else {
        subdivide(t1, t, p1, midPoint, p2, p3)
        subdivide(t, t2, p2, p3, midPoint, p4)
      }
    }

    subdivide(0, 1, start, control1, control2, end)
    points.append(end)
    return points
  }

  private func evaluateQuadCurve(t: Float, start: Point, control: Point, end: Point) -> Point {
    let u = 1 - t
    let tt = t * t
    let uu = u * u
    let uut = 2 * u * t

    return Point(
      uu * start.x + uut * control.x + tt * end.x,
      uu * start.y + uut * control.y + tt * end.y
    )
  }

  private func evaluateCubicCurve(t: Float, start: Point, control1: Point, control2: Point, end: Point) -> Point {
    let u = 1 - t
    let tt = t * t
    let ttt = tt * t
    let uu = u * u
    let uuu = uu * u
    let uut = 3 * uu * t
    let utt = 3 * u * tt

    return Point(
      uuu * start.x + uut * control1.x + utt * control2.x + ttt * end.x,
      uuu * start.y + uut * control1.y + utt * control2.y + ttt * end.y
    )
  }

  private func calculateQuadFlatness(p1: Point, p2: Point, p3: Point) -> Float {
    let dx1 = p2.x - p1.x
    let dy1 = p2.y - p1.y
    let dx2 = p3.x - p2.x
    let dy2 = p3.y - p2.y

    return abs(dx1 * dy2 - dy1 * dx2)
  }

  private func calculateCubicFlatness(p1: Point, p2: Point, p3: Point, p4: Point) -> Float {
    let dx1 = p2.x - p1.x
    let dy1 = p2.y - p1.y
    let dx2 = p3.x - p2.x
    let dy2 = p3.y - p2.y
    let dx3 = p4.x - p3.x
    let dy3 = p4.y - p3.y

    return abs(dx1 * dy2 - dy1 * dx2) + abs(dx2 * dy3 - dy2 * dx3)
  }
}

// MARK: - Stroke Generation

extension BezierPath {
  /// Generates stroke vertices for the path with the specified line width.
  /// - Parameter lineWidth: The width of the stroke.
  /// - Returns: An array of vertices representing the stroke geometry.
  public func generateStrokeVertices(lineWidth: Float) -> [Float] {
    var vertices: [Float] = []
    let halfWidth = lineWidth / 2

    // Get all points from the path
    var points: [Point] = []
    var currentPoint = Point(0, 0)

    for element in pathElements {
      switch element {
      case .moveTo(let point):
        currentPoint = point
        points.append(point)
      case .lineTo(let point):
        currentPoint = point
        points.append(point)
      case .quadCurveTo(let endPoint, let control):
        // Tessellate the curve to get points
        let tessellated = tessellateQuadCurve(from: currentPoint, to: endPoint, control: control, tolerance: 1.0)
        points.append(contentsOf: tessellated.dropFirst())
        currentPoint = endPoint
      case .curveTo(let endPoint, let control1, let control2):
        // Tessellate the curve to get points
        let tessellated = tessellateCubicCurve(
          from: currentPoint, to: endPoint, control1: control1, control2: control2, tolerance: 1.0)
        points.append(contentsOf: tessellated.dropFirst())
        currentPoint = endPoint
      case .closePath:
        if !points.isEmpty {
          points.append(points[0])  // Close the path
        }
      }
    }

    // Create stroke geometry for each line segment
    for i in 0..<(points.count - 1) {
      let start = points[i]
      let end = points[i + 1]
      addLineStroke(from: start, to: end, width: halfWidth, vertices: &vertices)
    }

    return vertices
  }

  /// Generates stroke vertices and indices for the path with the specified line width.
  /// - Parameter lineWidth: The width of the stroke.
  /// - Returns: A tuple containing vertices and indices for triangle rendering.
  public func generateStrokeGeometry(lineWidth: Float) -> (vertices: [Float], indices: [UInt32]) {
    let vertices = generateStrokeVertices(lineWidth: lineWidth)

    // Create triangle indices for stroke
    var indices: [UInt32] = []
    let vertexCount = vertices.count / 2
    for i in stride(from: 0, to: vertexCount - 2, by: 2) {
      indices.append(contentsOf: [UInt32(i), UInt32(i + 1), UInt32(i + 2)])
      indices.append(contentsOf: [UInt32(i + 1), UInt32(i + 3), UInt32(i + 2)])
    }

    return (vertices, indices)
  }

  private func addLineStroke(from start: Point, to end: Point, width: Float, vertices: inout [Float]) {
    // Calculate perpendicular vector for stroke width
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = sqrt(dx * dx + dy * dy)
    guard length > 0 else { return }

    let perpX = -dy / length * width
    let perpY = dx / length * width

    // Add stroke quad vertices (two triangles per line segment)
    vertices.append(contentsOf: [
      start.x + perpX, start.y + perpY,  // outer start
      start.x - perpX, start.y - perpY,  // inner start
      end.x + perpX, end.y + perpY,  // outer end
      end.x - perpX, end.y - perpY,  // inner end
    ])
  }
}
