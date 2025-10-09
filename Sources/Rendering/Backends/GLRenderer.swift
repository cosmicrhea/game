import Foundation
import GL

public final class GLRenderer: Renderer {
  private let imageProgram: GLProgram
  private let pathProgram: GLProgram

  // MARK: - State Management

  struct GLState {
    let depthTestEnabled: Bool
    let cullFaceEnabled: Bool
    let depthMaskEnabled: GLboolean
    let polygonMode: GLenum
  }

  private func saveGLState() -> GLState {
    let depthTestEnabled = glIsEnabled(GL_DEPTH_TEST)
    let cullFaceEnabled = glIsEnabled(GL_CULL_FACE)

    var depthMaskEnabled: GLboolean = false
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMaskEnabled)

    var polygonMode: [GLint] = [0, 0]
    polygonMode.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }

    return GLState(
      depthTestEnabled: depthTestEnabled,
      cullFaceEnabled: cullFaceEnabled,
      depthMaskEnabled: depthMaskEnabled,
      polygonMode: GLenum(polygonMode[0])
    )
  }

  private func restoreGLState(_ state: GLState) {
    glDepthMask(state.depthMaskEnabled)
    if state.depthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if state.cullFaceEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
    glPolygonMode(GL_FRONT_AND_BACK, state.polygonMode)
  }

  private func configureUIState() {
    glDepthMask(false)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)
  }

  // MARK: - Public State Management API

  /// Saves current OpenGL state and configures it for UI rendering (no depth testing, blending enabled)
  /// Returns a state object that should be passed to restoreUIState when done
  static func saveAndConfigureUIState() -> GLState {
    let depthTestEnabled = glIsEnabled(GL_DEPTH_TEST)
    let cullFaceEnabled = glIsEnabled(GL_CULL_FACE)

    var depthMaskEnabled: GLboolean = false
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMaskEnabled)

    var polygonMode: [GLint] = [0, 0]
    polygonMode.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }

    // Configure for UI rendering
    glDepthMask(false)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    return GLState(
      depthTestEnabled: depthTestEnabled,
      cullFaceEnabled: cullFaceEnabled,
      depthMaskEnabled: depthMaskEnabled,
      polygonMode: GLenum(polygonMode[0])
    )
  }

  /// Restores OpenGL state from a previously saved state
  static func restoreUIState(_ state: GLState) {
    glDepthMask(state.depthMaskEnabled)
    if state.depthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if state.cullFaceEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
    glPolygonMode(GL_FRONT_AND_BACK, state.polygonMode)
  }

  public init() {
    self.imageProgram = try! GLProgram("UI/text", "UI/image")
    self.pathProgram = try! GLProgram("Common/path", "Common/path")

    // Enable depth testing
    glEnable(GL_DEPTH_TEST)

    // Enable MSAA for antialiasing - this handles all antialiasing automatically
    glEnable(GL_MULTISAMPLE)
  }

  public func beginFrame(viewportSize: Size, scale: Float) {
    glViewport(0, 0, GLsizei(viewportSize.width), GLsizei(viewportSize.height))

    // Clear the screen and set up OpenGL state
    glClearColor(0.2, 0.1, 0.1, 1)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    //    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)  // Default to filled polygons
  }

  public func setWireframeMode(_ enabled: Bool) {
    let mode = enabled ? GL_LINE : GL_FILL
    glPolygonMode(GL_FRONT_AND_BACK, mode)
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
    let savedState = Self.saveAndConfigureUIState()

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

    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore state
    restoreGLState(savedState)

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
    //print("GLRenderer.drawImageRegion: textureID=\(textureID), rect=\(rect), uv=\(uv)")
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

    let savedState = saveGLState()
    configureUIState()

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

    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    restoreGLState(savedState)

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

  public func drawText(
    _ attributedString: AttributedString,
    at origin: Point,
    defaultStyle: TextStyle,
    wrapWidth: Float? = nil,
    anchor: TextAnchor = .topLeft
  ) {
    // Create a ModularTextRenderer for the default style
    guard let textRenderer = ModularTextRenderer(fontName: defaultStyle.fontName, pixelHeight: defaultStyle.fontSize)
    else {
      return
    }

    // Get current viewport size from OpenGL
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let windowSize = (w: Int32(viewport[2]), h: Int32(viewport[3]))

    // TODO: Implement proper attributed text rendering with per-character colors
    // For now, we just render the plain text with the default style

    // Convert TextAnchor to ModularTextRenderer.Anchor
    let modularAnchor: ModularTextRenderer.Anchor = {
      switch anchor {
      case .topLeft: return .topLeft
      case .bottomLeft: return .bottomLeft
      case .baselineLeft: return .baselineLeft
      }
    }()

    // Get outline color and thickness from stroke attributes
    let outlineColor = attributedString.attributes.compactMap { $0.stroke?.color }.first
    let outlineThickness = attributedString.attributes.compactMap { $0.stroke?.width }.first ?? 0

    // Draw using ModularTextRenderer (simplified to plain text for now)
    // TODO: Implement proper attributed text rendering
    textRenderer.draw(
      attributedString.string,
      at: (origin.x, origin.y),
      windowSize: windowSize,
      color: (defaultStyle.color.red, defaultStyle.color.green, defaultStyle.color.blue, defaultStyle.color.alpha),
      scale: 1.0,
      wrapWidth: wrapWidth,
      anchor: modularAnchor,
      outlineColor: outlineColor.map { ($0.red, $0.green, $0.blue, $0.alpha) },
      outlineThickness: outlineThickness
    )
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
    let (vertices, indices) = path.generateStrokeGeometry(lineWidth: lineWidth)
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    drawTriangles(vertices: vertices, indices: indices, color: color)
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
    let savedState = saveGLState()
    glDepthMask(false)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)

    pathProgram.use()
    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore state
    restoreGLState(savedState)

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }
}
