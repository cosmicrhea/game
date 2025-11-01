import Foundation

extension vec3 {
  /// Draw a simple debug arrow in screen space by projecting a world-space start and direction.
  /// - Parameters:
  ///   - direction: world-space direction (will be normalized)
  ///   - length: length in world units
  ///   - color: stroke color
  ///   - projection: camera projection matrix
  ///   - view: camera view matrix
  ///   - model: model transform (defaults to identity)
  public func drawDebugArrow(
    direction: vec3,
    length: Float,
    color: Color,
    projection: mat4,
    view: mat4,
    model: mat4 = mat4(1)
  ) {
    // Legacy 2D projected arrow implementation
    guard let renderer = GraphicsContext.current?.renderer else { return }

    func mul(_ m: mat4, _ v: vec4) -> vec4 {
      let r0 = m[0]
      let r1 = m[1]
      let r2 = m[2]
      let r3 = m[3]
      return vec4(
        r0.x * v.x + r0.y * v.y + r0.z * v.z + r0.w * v.w,
        r1.x * v.x + r1.y * v.y + r1.z * v.z + r1.w * v.w,
        r2.x * v.x + r2.y * v.y + r2.z * v.z + r2.w * v.w,
        r3.x * v.x + r3.y * v.y + r3.z * v.z + r3.w * v.w
      )
    }

    func project(_ p: vec3) -> Point? {
      let mvp = projection * view * model
      let clip = mul(mvp, vec4(p.x, p.y, p.z, 1))
      if clip.w == 0 { return nil }
      let ndc = vec3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
      let vp = Engine.viewportSize
      let x = (ndc.x * 0.5 + 0.5) * vp.width
      let y = (ndc.y * 0.5 + 0.5) * vp.height
      return Point(x, y)
    }

    let dir = normalize(direction) * length
    guard let a = project(self), let b = project(self + dir) else { return }

    // Main line
    var path = BezierPath()
    path.move(to: a)
    path.addLine(to: b)
    renderer.drawStroke(path, color: color, lineWidth: 2)

    // Arrow head
    let dx = b.x - a.x
    let dy = b.y - a.y
    let len = Swift.max(0.0001, sqrt(dx * dx + dy * dy))
    let ux = dx / len
    let uy = dy / len
    let head: Float = 8
    let perpX = -uy
    let perpY = ux
    let h1 = Point(b.x - ux * head + perpX * head * 0.5, b.y - uy * head + perpY * head * 0.5)
    let h2 = Point(b.x - ux * head - perpX * head * 0.5, b.y - uy * head - perpY * head * 0.5)

    var headPath = BezierPath()
    headPath.move(to: b)
    headPath.addLine(to: h1)
    headPath.move(to: b)
    headPath.addLine(to: h2)
    renderer.drawStroke(headPath, color: color, lineWidth: 2)
  }

  /// Draw a 3D debug arrow in world space using volumetric geometry
  /// - Parameters:
  ///   - direction: world-space direction (will be normalized)
  ///   - length: length in world units
  ///   - color: stroke color
  ///   - projection: camera projection matrix
  ///   - view: camera view matrix
  ///   - headLength: Length of the arrowhead (default: 10% of length)
  ///   - headRadius: Radius of the arrowhead base (default: 3% of length)
  ///   - lineThickness: Thickness multiplier for the arrow (default: 1.0)
  ///   - depthTest: Whether to enable depth testing (default: true)
  public func drawDebugArrow3D(
    direction: vec3,
    length: Float = 1.0,
    color: Color = .magenta,
    projection: mat4,
    view: mat4,
    headLength: Float? = nil,
    headRadius: Float? = nil,
    lineThickness: Float = 8.0,
    depthTest: Bool = true
  ) {
    guard let renderer = GraphicsContext.current?.renderer as? GLRenderer else { return }

    let dir = normalize(direction) * length
    let to = self + dir

    renderer.drawDebugArrow3D(
      from: self,
      to: to,
      color: color,
      projection: projection,
      view: view,
      headLength: headLength,
      headRadius: headRadius,
      lineThickness: lineThickness,
      depthTest: depthTest
    )
  }

  /// Draw a 3D debug line between two points
  public func drawDebugLine(to end: vec3, color: Color, projection: mat4, view: mat4, depthTest: Bool = true) {
    // Use 2D projection for simple line drawing
    guard let renderer = GraphicsContext.current?.renderer else { return }

    func mul(_ m: mat4, _ v: vec4) -> vec4 {
      let r0 = m[0]
      let r1 = m[1]
      let r2 = m[2]
      let r3 = m[3]
      return vec4(
        r0.x * v.x + r0.y * v.y + r0.z * v.z + r0.w * v.w,
        r1.x * v.x + r1.y * v.y + r1.z * v.z + r1.w * v.w,
        r2.x * v.x + r2.y * v.y + r2.z * v.z + r2.w * v.w,
        r3.x * v.x + r3.y * v.y + r3.z * v.z + r3.w * v.w
      )
    }

    func project(_ p: vec3) -> Point? {
      let mvp = projection * view
      let clip = mul(mvp, vec4(p.x, p.y, p.z, 1))
      if abs(clip.w) < 0.0001 { return nil }
      let ndc = vec3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
      // Only draw if in front of camera
      if ndc.z < -1.0 || ndc.z > 1.0 { return nil }
      let vp = Engine.viewportSize
      let x = (ndc.x * 0.5 + 0.5) * vp.width
      let y = (1.0 - (ndc.y * 0.5 + 0.5)) * vp.height  // Flip Y
      return Point(x, y)
    }

    guard let startPoint = project(self), let endPoint = project(end) else { return }

    // Draw line
    var path = BezierPath()
    path.move(to: startPoint)
    path.addLine(to: endPoint)
    renderer.drawStroke(path, color: color, lineWidth: 1)
  }
}
