import struct GLMath.Quaternion
import struct GLMath.Vector2
import struct GLMath.Vector3
import struct GLMath.Vector4
import struct Jolt.AABB
import struct Jolt.IndexedTriangle
import struct Jolt.Mat44
import struct Jolt.Plane
import struct Jolt.Quat
import struct Jolt.RMat44
import struct Jolt.RVec3
import struct Jolt.Triangle
import struct Jolt.Vec3

// MARK: - Point Conversions

extension Point {
  /// Creates a point from a Jolt Vec3, using the x and y components.
  /// - Parameter vec3: The Vec3 to convert (z component is ignored).
  public init(_ vec3: Vec3) {
    self.x = vec3.x
    self.y = vec3.y
  }

  /// Creates a point from a Jolt RVec3, using the x and y components.
  /// - Parameter rvec3: The RVec3 to convert (z component is ignored).
  public init(_ rvec3: RVec3) {
    self.x = rvec3.x
    self.y = rvec3.y
  }
}

extension Vec3 {
  /// Creates a Vec3 from a Point, setting z to 0.
  /// - Parameter point: The Point to convert.
  public init(_ point: Point) {
    self.init(x: point.x, y: point.y, z: 0)
  }
}

extension RVec3 {
  /// Creates an RVec3 from a Point, setting z to 0.
  /// - Parameter point: The Point to convert.
  public init(_ point: Point) {
    self.init(x: point.x, y: point.y, z: 0)
  }
}

// MARK: - Size Conversions

extension Size {
  /// Creates a size from a Jolt Vec3, using x as width and y as height.
  /// - Parameter vec3: The Vec3 to convert (z component is ignored).
  public init(_ vec3: Vec3) {
    self.width = vec3.x
    self.height = vec3.y
  }

  /// Creates a size from a Jolt RVec3, using x as width and y as height.
  /// - Parameter rvec3: The RVec3 to convert (z component is ignored).
  public init(_ rvec3: RVec3) {
    self.width = rvec3.x
    self.height = rvec3.y
  }
}

extension Vec3 {
  /// Creates a Vec3 from a Size, using width as x and height as y, with z set to 0.
  /// - Parameter size: The Size to convert.
  public init(_ size: Size) {
    self.init(x: size.width, y: size.height, z: 0)
  }
}

extension RVec3 {
  /// Creates an RVec3 from a Size, using width as x and height as y, with z set to 0.
  /// - Parameter size: The Size to convert.
  public init(_ size: Size) {
    self.init(x: size.width, y: size.height, z: 0)
  }
}

// MARK: - Rect Conversions

extension Rect {
  /// Creates a rectangle from a Jolt AABB, using the min point as origin and size from the extent.
  /// - Parameter aabb: The AABB to convert (z component of bounds is ignored).
  public init(_ aabb: AABB) {
    let origin = Point(aabb.min)
    let max = Point(aabb.max)
    let size = Size(max.x - origin.x, max.y - origin.y)
    self.init(origin: origin, size: size)
  }
}

extension AABB {
  /// Creates an AABB from a Rect, treating the rectangle as a 2D bounding box with z=0.
  /// - Parameter rect: The Rect to convert.
  public init(_ rect: Rect) {
    let minPoint = Vec3(rect.origin)
    let maxPoint = Vec3(
      x: rect.origin.x + rect.size.width,
      y: rect.origin.y + rect.size.height,
      z: 0
    )
    self.init(min: minPoint, max: maxPoint)
  }
}

// MARK: - GLMath Conversions

// MARK: - Point GLMath Conversions

extension Point {
  /// Creates a point from a GLMath vec2, using the x and y components.
  /// - Parameter vec2: The vec2 to convert.
  public init(_ vec2: Vector2<Float>) {
    self.x = vec2.x
    self.y = vec2.y
  }

  /// Creates a point from a GLMath vec3, using the x and y components.
  /// - Parameter vec3: The vec3 to convert (z component is ignored).
  public init(_ vec3: Vector3<Float>) {
    self.x = vec3.x
    self.y = vec3.y
  }
}

extension Vector2 where T == Float {
  /// Creates a vec2 from a Point.
  /// - Parameter point: The Point to convert.
  public init(_ point: Point) {
    self.init(point.x, point.y)
  }
}

extension Vector3 where T == Float {
  /// Creates a vec3 from a Point, setting z to 0.
  /// - Parameter point: The Point to convert.
  public init(_ point: Point) {
    self.init(point.x, point.y, 0)
  }
}

// MARK: - Size GLMath Conversions

extension Size {
  /// Creates a size from a GLMath vec2, using x as width and y as height.
  /// - Parameter vec2: The vec2 to convert.
  public init(_ vec2: Vector2<Float>) {
    self.width = vec2.x
    self.height = vec2.y
  }

  /// Creates a size from a GLMath vec3, using x as width and y as height.
  /// - Parameter vec3: The vec3 to convert (z component is ignored).
  public init(_ vec3: Vector3<Float>) {
    self.width = vec3.x
    self.height = vec3.y
  }
}

extension Vector2 where T == Float {
  /// Creates a vec2 from a Size, using width as x and height as y.
  /// - Parameter size: The Size to convert.
  public init(_ size: Size) {
    self.init(size.width, size.height)
  }
}

extension Vector3 where T == Float {
  /// Creates a vec3 from a Size, using width as x and height as y, with z set to 0.
  /// - Parameter size: The Size to convert.
  public init(_ size: Size) {
    self.init(size.width, size.height, 0)
  }
}

// MARK: - Jolt ↔ GLMath Vector Conversions

extension Vec3 {
  /// Creates a Jolt Vec3 from a GLMath vec3.
  /// - Parameter vec3: The GLMath vec3 to convert.
  public init(_ vec3: Vector3<Float>) {
    self.init(x: vec3.x, y: vec3.y, z: vec3.z)
  }
}

extension Vector3 where T == Float {
  /// Creates a GLMath vec3 from a Jolt Vec3.
  /// - Parameter vec3: The Jolt Vec3 to convert.
  public init(_ vec3: Vec3) {
    self.init(vec3.x, vec3.y, vec3.z)
  }
}

extension RVec3 {
  /// Creates a Jolt RVec3 from a GLMath vec3.
  /// - Parameter vec3: The GLMath vec3 to convert.
  public init(_ vec3: Vector3<Float>) {
    self.init(x: vec3.x, y: vec3.y, z: vec3.z)
  }
}

extension Vector3 where T == Float {
  /// Creates a GLMath vec3 from a Jolt RVec3.
  /// - Parameter rvec3: The Jolt RVec3 to convert.
  public init(_ rvec3: RVec3) {
    self.init(rvec3.x, rvec3.y, rvec3.z)
  }
}

// MARK: - Quaternion Conversions

extension Quat {
  /// Creates a Jolt Quat from a GLMath Quaternion.
  /// - Parameter quat: The GLMath Quaternion to convert.
  public init(_ quat: Quaternion<Float>) {
    self.init(x: quat.x, y: quat.y, z: quat.z, w: quat.w)
  }
}

extension Quaternion where T == Float {
  /// Creates a GLMath Quaternion from a Jolt Quat.
  /// - Parameter quat: The Jolt Quat to convert.
  public init(_ quat: Quat) {
    self.init(quat.x, quat.y, quat.z, quat.w)
  }
}
