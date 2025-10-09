import Foundation
import GL

public final class GLRenderer: Renderer {
  private let imageProgram: GLProgram
  private let pathProgram: GLProgram

  public init() {
    // Reuse existing shaders for UI text/image
    self.imageProgram = try! GLProgram("UI/text", "UI/image")
    self.pathProgram = try! GLProgram("Common/path", "Common/path")
  }

  public func beginFrame(viewportSize: Size, scale: Float) {
    glViewport(0, 0, GLsizei(viewportSize.width), GLsizei(viewportSize.height))
  }

  public func endFrame() {
    // no-op for now
  }

  public func drawImage(
    textureID: UInt64,
    in rect: Rect,
    tint: Color?
  ) {
    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    // Quad vertices: x, y, u, v
    let verts: [Float] = [
      x, y, 0, 0,
      x + w, y, 1, 0,
      x + w, y + h, 1, 1,
      x, y + h, 0, 1,
    ]
    let indices: [UInt32] = [0, 1, 2, 2, 3, 0]

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(
      GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts, GL_DYNAMIC_DRAW
    )
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices,
      GL_DYNAMIC_DRAW)

    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0)
    )
    let uvOff = UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), uvOff)

    // Ortho MVP will be set by caller shaders expecting uMVP; set to identity-like in pixel space.
    // We don't have viewport here; rely on the shader behaving like ImageRenderer.
    // For now, mimic ImageRenderer's usage path: set uniforms each call.
    // NOTE: For a real impl, pass viewport size into GLRenderer to compute MVP.

    // Save state and configure blending
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    imageProgram.use()
    // The shader expects uMVP; use an orthographic matrix using current viewport
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let W = Float(viewport[2])
    let H = Float(viewport[3])
    let mvp: [Float] = [
      2 / W, 0, 0, 0,
      0, 2 / H, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]
    mvp.withUnsafeBufferPointer { buf in
      imageProgram.setMat4("uMVP", value: buf.baseAddress!)
    }

    let tintColor = tint ?? .white
    imageProgram.setVec4("uTint", value: (tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, GLuint(textureID))
    imageProgram.setInt("uTexture", value: 0)

    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore state
    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  public func drawImageRegion(
    textureID: UInt64,
    in rect: Rect,
    uv: Rect,
    tint: Color?
  ) {
    print("GLRenderer.drawImageRegion: textureID=\(textureID), rect=\(rect), uv=\(uv)")
    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height
    let u0 = uv.origin.x
    let v0 = uv.origin.y
    let u1 = uv.origin.x + uv.size.width
    let v1 = uv.origin.y + uv.size.height

    let verts: [Float] = [
      x, y, u0, v0,
      x + w, y, u1, v0,
      x + w, y + h, u1, v1,
      x, y + h, u0, v1,
    ]
    let indices: [UInt32] = [0, 1, 2, 2, 3, 0]

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts, GL_DYNAMIC_DRAW)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_DYNAMIC_DRAW)

    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), UnsafeRawPointer(bitPattern: 0))
    let uvOff = UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), uvOff)

    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    imageProgram.use()
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let W = Float(viewport[2])
    let H = Float(viewport[3])
    let mvp: [Float] = [
      2 / W, 0, 0, 0,
      0, 2 / H, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]
    mvp.withUnsafeBufferPointer { buf in
      imageProgram.setMat4("uMVP", value: buf.baseAddress!)
    }

    let tintColor = tint ?? .white
    imageProgram.setVec4("uTint", value: (tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, GLuint(textureID))
    imageProgram.setInt("uTexture", value: 0)

    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  public func drawGlyphs(
    atlasID: UInt64,
    vertices: UnsafeBufferPointer<Float>,
    color: Color
  ) {
    // TODO: Wire to ModularTextRenderer or a minimal glyph pipeline.
  }

  public func setClipRect(_ rect: Rect?) {
    if let r = rect {
      glEnable(GL_SCISSOR_TEST)
      glScissor(GLint(r.origin.x), GLint(r.origin.y), GLsizei(r.size.width), GLsizei(r.size.height))
    } else {
      glDisable(GL_SCISSOR_TEST)
    }
  }

  public func drawPath(_ path: BezierPath, color: Color) {
    let (vertices, indices) = path.tessellate()
    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  public func drawStroke(_ path: BezierPath, color: Color, lineWidth: Float) {
    // Create stroke by drawing the path as a thick line
    // This is a simplified stroke implementation
    let strokeVertices = createStrokeVertices(from: path, lineWidth: lineWidth)
    guard !strokeVertices.isEmpty else { return }

    // Create triangle indices for stroke
    var indices: [UInt32] = []
    let vertexCount = strokeVertices.count / 2
    for i in stride(from: 0, to: vertexCount - 2, by: 2) {
      indices.append(contentsOf: [UInt32(i), UInt32(i + 1), UInt32(i + 2)])
      indices.append(contentsOf: [UInt32(i + 1), UInt32(i + 3), UInt32(i + 2)])
    }

    drawTriangles(vertices: strokeVertices, indices: indices, color: color)
  }

  private func createStrokeVertices(from path: BezierPath, lineWidth: Float) -> [Float] {
    var vertices: [Float] = []
    let halfWidth = lineWidth / 2

    // Get all points from the path
    var points: [Point] = []
    var currentPoint = Point(0, 0)

    for element in path.pathElements {
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

  // Helper functions for curve tessellation (simplified versions)
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

  private func drawTriangles(vertices: [Float], indices: [UInt32], color: Color) {
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(
      GL_ARRAY_BUFFER,
      vertices.count * MemoryLayout<Float>.stride,
      vertices,
      GL_DYNAMIC_DRAW
    )
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER,
      indices.count * MemoryLayout<UInt32>.stride,
      indices,
      GL_DYNAMIC_DRAW
    )

    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(2 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0)
    )

    // Set up orthographic projection matrix
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let W = Float(viewport[2])
    let H = Float(viewport[3])
    let mvp: [Float] = [
      2 / W, 0, 0, 0,
      0, 2 / H, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]
    mvp.withUnsafeBufferPointer { buf in
      pathProgram.setMat4("uMVP", value: buf.baseAddress!)
    }

    pathProgram.setVec4("uColor", value: (color.red, color.green, color.blue, color.alpha))

    // Save current state
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)

    pathProgram.use()
    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore state
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }
}
