import Foundation
import GL
import GLMath
import STBTrueType

public final class GLRenderer: Renderer {
  private let imageProgram: GLProgram
  private let pathProgram: GLProgram
  private let textProgram: GLProgram
  private let fboProgram: GLProgram
  private let gradientProgram: GLProgram

  // Clear color state
  private var clearColor = Color(0.2, 0.1, 0.1, 1.0)

  // Viewport state
  private var _viewportSize: Size = Size(1280, 720)  // Default fallback
  private var frameCount: Int = 0

  public var viewportSize: Size {
    // Try to get current viewport from OpenGL, fallback to stored value
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    if viewport[2] > 0 && viewport[3] > 0 {
      return Size(Float(viewport[2]), Float(viewport[3]))
    }
    return _viewportSize
  }

  // MARK: - UI State Management

  /// Execute a block with UI rendering state (no depth testing, blending enabled)
  static func withUIContext<T>(_ block: () throws -> T) rethrows -> T {
    // Save current state
    let depthTest = glIsEnabled(GL_DEPTH_TEST)
    let cullFace = glIsEnabled(GL_CULL_FACE)

    var depthMask: GLboolean = false
    glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask)

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

    defer {
      // Restore previous state
      glDepthMask(depthMask)
      if depthTest { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
      if cullFace { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
      glPolygonMode(GL_FRONT_AND_BACK, GLenum(polygonMode[0]))
    }

    return try block()
  }

  /// Execute a block with UI rendering state (no depth testing, blending enabled)
  public func withUIContext<T>(_ block: () throws -> T) rethrows -> T {
    return try Self.withUIContext(block)
  }

  // MARK: - Renderer

  public init() {
    self.imageProgram = try! GLProgram("UI/image", "UI/image")
    self.pathProgram = try! GLProgram("Common/path", "Common/path")
    self.textProgram = try! GLProgram("UI/text")
    self.fboProgram = try! GLProgram("UI/fbo", "UI/fbo")
    self.gradientProgram = try! GLProgram("Common/gradient", "Common/gradient")

    // Enable depth testing
    glEnable(GL_DEPTH_TEST)

    // Enable MSAA for antialiasing - this handles all antialiasing automatically
    glEnable(GL_MULTISAMPLE)
  }

  public func beginFrame(windowSize: Size) {
    // Set the viewport to match the window size
    glViewport(0, 0, GLsizei(windowSize.width), GLsizei(windowSize.height))

    // Update our stored viewport size
    if windowSize != _viewportSize {
      _viewportSize = windowSize
    }

    // Clear the screen and set up OpenGL state
    glClearColor(clearColor.red, clearColor.green, clearColor.blue, clearColor.alpha)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
    //    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)  // Default to filled polygons
  }

  public func setWireframeMode(_ enabled: Bool) {
    let mode = enabled ? GL_LINE : GL_FILL
    glPolygonMode(GL_FRONT_AND_BACK, mode)
  }

  public func setClearColor(_ color: Color) {
    clearColor = color
  }

  public func endFrame() {
    // no-op for now
  }

  public func drawImage(
    textureID: UInt64,
    in rect: Rect,
    tint: Color?
  ) {
    // Apply coordinate flipping if the current GraphicsContext is flipped
    let finalRect: Rect
    if let context = GraphicsContext.current, context.isFlipped {
      finalRect = context.flipRect(rect)
    } else {
      finalRect = rect
    }

    let x = finalRect.origin.x
    let y = finalRect.origin.y
    let w = finalRect.size.width
    let h = finalRect.size.height

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
    Self.withUIContext {
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
    }

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

    // Apply coordinate flipping if the current GraphicsContext is flipped
    let finalRect: Rect
    if let context = GraphicsContext.current, context.isFlipped {
      finalRect = context.flipRect(rect)
    } else {
      finalRect = rect
    }

    let x = finalRect.origin.x
    let y = finalRect.origin.y
    let w = finalRect.size.width
    let h = finalRect.size.height
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

    Self.withUIContext {
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
    }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  public func drawText(
    _ attributedString: AttributedString,
    at origin: Point,
    defaultStyle: TextStyle,
    wrapWidth: Float? = nil,
    alignment: Alignment = .topLeft,
    textAlignment: TextAlignment = .left
  ) {
    // Apply coordinate flipping if the current GraphicsContext is flipped
    let finalOrigin: Point
    if let context = GraphicsContext.current, context.isFlipped {
      finalOrigin = context.flipPoint(origin)
    } else {
      finalOrigin = origin
    }
    // Create font and layout for the default style
    guard let font = Font(fontName: defaultStyle.fontName, pixelHeight: defaultStyle.fontSize) else {
      return
    }

    let layout = TextLayout(font: font, scale: 1.0)

    // Get current viewport size from OpenGL
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let windowSize = (w: Int32(viewport[2]), h: Int32(viewport[3]))

    let text = attributedString.string
    let currentScale: Float = 1.0

    // Layout the text using TextStyle (respects lineHeight)
    let layoutResult = layout.layout(
      text,
      style: defaultStyle,
      wrapWidth: wrapWidth
    )

    let lineHeight = layoutResult.lineHeight * currentScale

    // Ensure we have an atlas for the required glyphs
    guard let atlas = GlyphAtlas.build(for: text, font: font.getTrueTypeFont()) else { return }

    // Convert Alignment to anchor offset
    let anchorOffset = calculateAlignmentOffset(
      layoutResult: layoutResult,
      origin: finalOrigin,
      alignment: alignment,
      scale: currentScale,
      font: font
    )

    // Generate vertices for all lines
    var allVertices: [Float] = []
    var allIndices: [UInt32] = []
    var indexOffset: UInt32 = 0

    for (_, line) in layoutResult.lines.enumerated() {
      // Calculate proper Y position for this line using the working approach
      let lineBaselineY = finalOrigin.y + anchorOffset.y - Float(line.baselineY) * lineHeight

      // Calculate X offset based on alignment
      let lineXOffset: Float
      if let wrapWidth = wrapWidth {
        switch alignment {
        case .topLeft, .left, .bottomLeft:
          lineXOffset = 0
        case .top, .center, .bottom:
          lineXOffset = (wrapWidth - line.width) / 2
        case .topRight, .right, .bottomRight:
          lineXOffset = wrapWidth - line.width
        case .baselineLeft:
          lineXOffset = 0
        }
      } else {
        lineXOffset = 0
      }

      let lineVertices = generateTextLineVertices(
        line: line,
        atlas: atlas,
        origin: Point(finalOrigin.x + anchorOffset.x + lineXOffset, lineBaselineY),
        scale: currentScale,
        color: defaultStyle.color,
        font: font
      )

      let lineIndices = generateTextLineIndices(
        vertexCount: lineVertices.count / 8,  // 8 components: x, y, u, v, r, g, b, a
        indexOffset: indexOffset
      )

      allVertices.append(contentsOf: lineVertices)
      allIndices.append(contentsOf: lineIndices)
      indexOffset += UInt32(lineVertices.count / 8)
    }

    // Get outline color and thickness from stroke attributes (prioritize attributed string, fall back to default style)
    let outlineColor = attributedString.attributes.compactMap { $0.stroke?.color }.first ?? defaultStyle.strokeColor
    let outlineThickness =
      attributedString.attributes.compactMap { $0.stroke?.width }.first ?? defaultStyle.strokeWidth

    // Get shadow attributes (prioritize attributed string, fall back to default style)
    let shadowColor = attributedString.attributes.compactMap { $0.shadow?.color }.first ?? defaultStyle.shadowColor
    let shadowOffset =
      attributedString.attributes.compactMap { $0.shadow?.offset }.first ?? defaultStyle.shadowOffset
    let shadowBlur =
      attributedString.attributes.compactMap { $0.shadow?.width }.first ?? defaultStyle.shadowWidth

    // Render the text using UI context
    withUIContext {
      renderTextVertices(
        allVertices,
        allIndices,
        atlas: atlas,
        color: defaultStyle.color,
        outlineColor: outlineColor,
        outlineThickness: outlineThickness,
        shadowColor: shadowColor,
        shadowOffset: shadowOffset,
        shadowBlur: shadowBlur,
        windowSize: windowSize
      )
    }
  }

  public func setClipRect(_ rect: Rect?) {
    if let r = rect {
      // Apply coordinate flipping if the current GraphicsContext is flipped
      let finalRect: Rect
      if let context = GraphicsContext.current, context.isFlipped {
        finalRect = context.flipRect(r)
      } else {
        finalRect = r
      }

      glEnable(GL_SCISSOR_TEST)
      glScissor(
        GLint(finalRect.origin.x), GLint(finalRect.origin.y), GLsizei(finalRect.size.width),
        GLsizei(finalRect.size.height))
    } else {
      glDisable(GL_SCISSOR_TEST)
    }
  }

  public func drawPath(_ path: BezierPath, color: Color) {
    // Apply coordinate flipping if the current GraphicsContext is flipped
    let finalPath: BezierPath
    if let context = GraphicsContext.current, context.isFlipped {
      // Create a flipped version of the path
      var newPath = BezierPath()
      for element in path.pathElements {
        switch element {
        case .moveTo(let point):
          newPath.move(to: context.flipPoint(point))
        case .lineTo(let point):
          newPath.addLine(to: context.flipPoint(point))
        case .quadCurveTo(let point, let control):
          newPath.addQuadCurve(to: context.flipPoint(point), control: context.flipPoint(control))
        case .curveTo(let point, let control1, let control2):
          newPath.addCurve(
            to: context.flipPoint(point), control1: context.flipPoint(control1), control2: context.flipPoint(control2))
        case .closePath:
          newPath.closePath()
        }
      }
      finalPath = newPath
    } else {
      finalPath = path
    }

    let (vertices, indices) = finalPath.tessellate()
    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  public func drawStroke(_ path: BezierPath, color: Color, lineWidth: Float) {
    // Apply coordinate flipping if the current GraphicsContext is flipped
    let finalPath: BezierPath
    if let context = GraphicsContext.current, context.isFlipped {
      // Create a flipped version of the path
      var newPath = BezierPath()
      for element in path.pathElements {
        switch element {
        case .moveTo(let point):
          newPath.move(to: context.flipPoint(point))
        case .lineTo(let point):
          newPath.addLine(to: context.flipPoint(point))
        case .quadCurveTo(let point, let control):
          newPath.addQuadCurve(to: context.flipPoint(point), control: context.flipPoint(control))
        case .curveTo(let point, let control1, let control2):
          newPath.addCurve(
            to: context.flipPoint(point), control1: context.flipPoint(control1), control2: context.flipPoint(control2))
        case .closePath:
          newPath.closePath()
        }
      }
      finalPath = newPath
    } else {
      finalPath = path
    }

    let (vertices, indices) = finalPath.generateStrokeGeometry(lineWidth: lineWidth)
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  // MARK: - Gradient Drawing

  public func drawLinearGradient(_ gradient: Gradient, in rect: Rect, angle: Float) {
    drawGradient(gradient, in: rect, type: 0, angle: angle, center: nil)
  }

  public func drawLinearGradient(_ gradient: Gradient, in path: BezierPath, angle: Float) {
    let (vertices, indices) = path.tessellate()
    guard !vertices.isEmpty && !indices.isEmpty else { return }
    let bounds = calculateBounds(from: vertices)
    drawGradientTriangles(
      gradient, vertices: vertices, indices: indices, type: 0, angle: angle, center: nil, bounds: bounds)
  }

  public func drawRadialGradient(_ gradient: Gradient, in rect: Rect, center: Point) {
    // TODO: Implement OpenGL gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      drawRect(rect, color: firstColor)
    }
  }

  public func drawRadialGradient(_ gradient: Gradient, in path: BezierPath, center: Point) {
    // TODO: Implement OpenGL gradient rendering
    // For now, fall back to solid color (first color stop)
    if let firstColor = gradient.colorStops.first?.color {
      drawPath(path, color: firstColor)
    }
  }

  private func createOrthographicMatrix(viewportSize: Size) -> [Float] {
    let left: Float = 0
    let right = viewportSize.width
    let bottom: Float = 0
    let top = viewportSize.height
    let near: Float = 0
    let far: Float = 1

    let m00 = 2 / (right - left)
    let m11 = 2 / (top - bottom)
    let m22 = -2 / (far - near)
    let m03 = -(right + left) / (right - left)
    let m13 = -(top + bottom) / (top - bottom)
    let m23 = -(far + near) / (far - near)

    return [
      m00, 0, 0, 0,
      0, m11, 0, 0,
      0, 0, m22, 0,
      m03, m13, m23, 1,
    ]
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

    // Save current state
    Self.withUIContext {
      pathProgram.use()

      // Set up orthographic projection matrix AFTER using the program
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

      glBindVertexArray(vao)
      glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  /// Draws a simple rectangle with a solid color (for fallback rendering)
  private func drawRect(_ rect: Rect, color: Color) {
    let vertices: [Float] = [
      // x, y, r, g, b, a
      rect.origin.x, rect.origin.y, color.red, color.green, color.blue, color.alpha,  // bottom-left
      rect.origin.x + rect.width, rect.origin.y, color.red, color.green, color.blue, color.alpha,  // bottom-right
      rect.origin.x, rect.origin.y + rect.height, color.red, color.green, color.blue, color.alpha,  // top-left
      rect.origin.x + rect.width, rect.origin.y + rect.height, color.red, color.green, color.blue, color.alpha,  // top-right
    ]

    let indices: [UInt32] = [0, 1, 2, 1, 3, 2]  // Two triangles

    drawTriangles(vertices: vertices, indices: indices, color: color)
  }

  // MARK: - Text Rendering Helpers

  private func calculateAlignmentOffset(
    layoutResult: TextLayout.LayoutResult,
    origin: Point,
    alignment: Alignment,
    scale: Float,
    font: Font
  ) -> Point {
    // Use the same approach as the working ModularTextRenderer
    let baseline = font.baselineFromTop * scale

    switch alignment {
    case .topLeft:
      return Point(0, -baseline)
    case .top:
      return Point(-layoutResult.totalWidth / 2, -baseline)
    case .topRight:
      return Point(-layoutResult.totalWidth, -baseline)
    case .left:
      return Point(0, layoutResult.totalHeight / 2 - baseline)
    case .center:
      return Point(-layoutResult.totalWidth / 2, layoutResult.totalHeight / 2 - baseline)
    case .right:
      return Point(-layoutResult.totalWidth, layoutResult.totalHeight / 2 - baseline)
    case .bottomLeft:
      return Point(0, layoutResult.totalHeight - baseline)
    case .bottom:
      return Point(-layoutResult.totalWidth / 2, layoutResult.totalHeight - baseline)
    case .bottomRight:
      return Point(-layoutResult.totalWidth, layoutResult.totalHeight - baseline)
    case .baselineLeft:
      return Point(0, 0)
    }
  }

  private func generateTextLineVertices(
    line: TextLayout.Line,
    atlas: GlyphAtlas,
    origin: Point,
    scale: Float,
    color: Color,
    font: Font
  ) -> [Float] {
    var vertices: [Float] = []
    var currentX: Float = 0

    // Generate glyphs from the text
    let scalars = Array(line.text.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let codepoint = Int32(scalars[i].value)

      // Handle spaces - they should advance but not render
      if codepoint == 32 {  // Space character
        // Use the actual font advance for spaces to match measurement
        // Spaces don't have glyphs in the atlas, so we get the advance directly from the font
        let spaceAdvance = font.getTrueTypeFont().getAdvance(for: codepoint, next: nil)
        currentX += spaceAdvance * scale
        i += 1
        continue
      }

      guard let glyphInfo = atlas.glyphs[codepoint] else {
        i += 1
        continue
      }

      // Position the glyph correctly using the working ModularTextRenderer approach
      let x0 = origin.x + currentX + Float(glyphInfo.xOffset) * scale
      let y1 = origin.y - Float(glyphInfo.yOffset) * scale  // NEGATE yOffset like the working code
      let y0 = y1 - Float(glyphInfo.height) * scale
      let x1 = x0 + Float(glyphInfo.width) * scale

      // Quad vertices: x, y, u, v, r, g, b, a (using working ModularTextRenderer approach)
      let quad: [Float] = [
        x0, y0, glyphInfo.u0, glyphInfo.v0, color.red, color.green, color.blue, color.alpha,  // bottom-left
        x1, y0, glyphInfo.u1, glyphInfo.v0, color.red, color.green, color.blue, color.alpha,  // bottom-right
        x1, y1, glyphInfo.u1, glyphInfo.v1, color.red, color.green, color.blue, color.alpha,  // top-right
        x0, y1, glyphInfo.u0, glyphInfo.v1, color.red, color.green, color.blue, color.alpha,  // top-left
      ]
      vertices.append(contentsOf: quad)

      // Advance to next character using proper advance
      currentX += Float(glyphInfo.advance) * scale
      i += 1
    }

    return vertices
  }

  private func generateTextLineIndices(vertexCount: Int, indexOffset: UInt32) -> [UInt32] {
    var indices: [UInt32] = []
    let quadCount = vertexCount / 4

    for i in 0..<quadCount {
      let base = indexOffset + UInt32(i * 4)
      let quad: [UInt32] = [
        base, base + 1, base + 2,
        base, base + 2, base + 3,
      ]
      indices.append(contentsOf: quad)
    }

    return indices
  }

  private func renderTextVertices(
    _ vertices: [Float],
    _ indices: [UInt32],
    atlas: GlyphAtlas,
    color: Color,
    outlineColor: Color?,
    outlineThickness: Float,
    shadowColor: Color? = nil,
    shadowOffset: Point = Point(0, 0),
    shadowBlur: Float = 0.0,
    windowSize: (w: Int32, h: Int32)
  ) {
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_DYNAMIC_DRAW)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_DYNAMIC_DRAW)

    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(8 * MemoryLayout<Float>.stride), UnsafeRawPointer(bitPattern: 0))
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(8 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride))
    glEnableVertexAttribArray(2)
    glVertexAttribPointer(
      2, 4, GL_FLOAT, false, GLsizei(8 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 4 * MemoryLayout<Float>.stride))

    // Set up MVP matrix
    let w = Float(windowSize.w)
    let h = Float(windowSize.h)
    let mvp: [Float] = [
      2 / w, 0, 0, 0,
      0, 2 / h, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]

    textProgram.use()
    mvp.withUnsafeBufferPointer { buffer in
      textProgram.setMat4("uMVP", value: buffer.baseAddress!)
    }

    // Draw shadow first if specified
    if let shadowColor = shadowColor, shadowBlur > 0 {
      textProgram.setVec4("uColor", value: (shadowColor.red, shadowColor.green, shadowColor.blue, shadowColor.alpha))

      // Create shadow vertices with offset
      var shadowVertices = vertices
      for i in stride(from: 0, to: shadowVertices.count, by: 8) {
        shadowVertices[i] += shadowOffset.x
        shadowVertices[i + 1] += shadowOffset.y
      }

      glBindBuffer(GL_ARRAY_BUFFER, vbo)
      glBufferData(GL_ARRAY_BUFFER, shadowVertices.count * MemoryLayout<Float>.stride, shadowVertices, GL_DYNAMIC_DRAW)

      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, atlas.texture)
      textProgram.setInt("uAtlas", value: 0)

      glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    }

    // Draw outline if specified
    if let outlineColor = outlineColor, outlineThickness > 0 {
      textProgram.setVec4(
        "uColor", value: (outlineColor.red, outlineColor.green, outlineColor.blue, outlineColor.alpha))

      let offsets: [(Float, Float)] = [
        (-outlineThickness, 0), (outlineThickness, 0),
        (0, -outlineThickness), (0, outlineThickness),
        (-outlineThickness, -outlineThickness), (outlineThickness, outlineThickness),
        (-outlineThickness, outlineThickness), (outlineThickness, -outlineThickness),
      ]

      for (offsetX, offsetY) in offsets {
        var offsetVertices = vertices
        for i in stride(from: 0, to: offsetVertices.count, by: 8) {
          offsetVertices[i] += offsetX
          offsetVertices[i + 1] += offsetY
        }

        glBindBuffer(GL_ARRAY_BUFFER, vbo)
        glBufferData(
          GL_ARRAY_BUFFER, offsetVertices.count * MemoryLayout<Float>.stride, offsetVertices, GL_DYNAMIC_DRAW)

        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, atlas.texture)
        textProgram.setInt("uAtlas", value: 0)

        glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
      }
    }

    // Draw fill
    textProgram.setVec4("uColor", value: (color.red, color.green, color.blue, color.alpha))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, atlas.texture)
    textProgram.setInt("uAtlas", value: 0)

    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_DYNAMIC_DRAW)

    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  // MARK: - Framebuffer Objects (FBO)

  private var framebuffers: [UInt64: GLFramebuffer] = [:]
  private var nextFramebufferID: UInt64 = 1

  public func createFramebuffer(size: Size, scale: Float) -> UInt64 {
    let id = nextFramebufferID
    nextFramebufferID += 1

    let framebuffer = GLFramebuffer(size: size, scale: scale)
    framebuffers[id] = framebuffer
    return id
  }

  public func destroyFramebuffer(_ framebufferID: UInt64) {
    framebuffers.removeValue(forKey: framebufferID)
  }

  public func beginFramebuffer(_ framebufferID: UInt64) {
    guard let framebuffer = framebuffers[framebufferID] else { return }
    framebuffer.bind()
  }

  public func endFramebuffer() {
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
  }

  public func getFramebufferTextureID(_ framebufferID: UInt64) -> UInt64? {
    guard let framebuffer = framebuffers[framebufferID] else { return nil }
    return framebuffer.getTextureID()
  }

  public func drawFramebuffer(
    _ framebufferID: UInt64,
    in rect: Rect,
    transform: Transform2D?,
    alpha: Float
  ) {
    guard let framebuffer = framebuffers[framebufferID] else {
      logger.error("🎨 FBO not found: \(framebufferID)")
      return
    }

    // Use the FBO program to draw the framebuffer texture
    withUIContext {
      fboProgram.use()

      // Get viewport for coordinate conversion
      var viewport: [GLint] = [0, 0, 0, 0]
      glGetIntegerv(GL_VIEWPORT, &viewport)
      let W = Float(viewport[2])
      let H = Float(viewport[3])

      // Create orthographic projection matrix
      let projection = GLMath.ortho(0, W, H, 0)

      // Convert transform to clip space
      let transformMatrix = transform?.toMatrix() ?? Transform2D().toMatrix()
      let mvp = projection * transformMatrix
      fboProgram.setMat4("uTransform", value: mvp)

      // Set alpha
      fboProgram.setFloat("uAlpha", value: alpha)

      // Draw the framebuffer texture
      framebuffer.drawTexture(in: rect, program: fboProgram)
    }
  }

  // MARK: - Gradient Helper Methods

  private func calculateBounds(from vertices: [Float]) -> Rect {
    guard !vertices.isEmpty else { return .zero }

    var minX = Float.infinity
    var maxX = -Float.infinity
    var minY = Float.infinity
    var maxY = -Float.infinity

    // Assuming vertices are in format [x, y, ...] with stride of 2
    for i in stride(from: 0, to: vertices.count, by: 2) {
      let x = vertices[i]
      let y = vertices[i + 1]

      minX = min(minX, x)
      maxX = max(maxX, x)
      minY = min(minY, y)
      maxY = max(maxY, y)
    }

    return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private func drawGradient(_ gradient: Gradient, in rect: Rect, type: Int, angle: Float, center: Point?) {
    // Create vertices for the rectangle with gradient coordinates
    let vertices: [Float] = [
      // x, y, gradientX, gradientY
      rect.origin.x, rect.origin.y, 0.0, 0.0,  // bottom-left
      rect.origin.x + rect.width, rect.origin.y, 1.0, 0.0,  // bottom-right
      rect.origin.x, rect.origin.y + rect.height, 0.0, 1.0,  // top-left
      rect.origin.x + rect.width, rect.origin.y + rect.height, 1.0, 1.0,  // top-right
    ]

    let indices: [UInt32] = [0, 1, 2, 1, 3, 2]  // Two triangles

    drawGradientTriangles(
      gradient, vertices: vertices, indices: indices, type: type, angle: angle, center: center, bounds: rect)
  }

  private func drawGradientTriangles(
    _ gradient: Gradient, vertices: [Float], indices: [UInt32], type: Int, angle: Float, center: Point?, bounds: Rect
  ) {
    guard !vertices.isEmpty && !indices.isEmpty else { return }

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0

    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_DYNAMIC_DRAW)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_DYNAMIC_DRAW)

    // Position attribute
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), UnsafeRawPointer(bitPattern: 0))

    // Gradient coordinate attribute
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride))

    // Use the gradient shader
    gradientProgram.use()

    // Set up uniforms using the proper GLProgram API
    let mvp = createOrthographicMatrix(viewportSize: viewportSize)
    mvp.withUnsafeBufferPointer { buf in
      gradientProgram.setMat4("mvp", value: buf.baseAddress!)
    }
    gradientProgram.setInt("gradientType", value: Int32(type))

    // Set gradient parameters based on type
    if type == 0 {
      // Linear gradient - use normalized coordinates (0,0) to (1,1) for diagonal
      let angleRad = angle * .pi / 180.0

      // Calculate start and end points in UV space (0,0) to (1,1)
      let cosAngle = cos(angleRad)
      let sinAngle = sin(angleRad)

      // For a diagonal gradient from bottom-left to top-right
      let startX = 0.5 - 0.5 * cosAngle
      let startY = 0.5 - 0.5 * sinAngle
      let endX = 0.5 + 0.5 * cosAngle
      let endY = 0.5 + 0.5 * sinAngle

      gradientProgram.setVec2("gradientStart", value: (startX, startY))
      gradientProgram.setVec2("gradientEnd", value: (endX, endY))
    } else {
      // Radial gradient - simple approach
      let centerX = center?.x ?? 0.5
      let centerY = center?.y ?? 0.5
      let maxRadius = 0.5  // Simple radius that covers the unit square

      gradientProgram.setVec2("gradientStart", value: (centerX, centerY))
      gradientProgram.setVec2("gradientEnd", value: (Float(maxRadius), 0.0))
    }

    // Set color stops
    let numStops = min(gradient.colorStops.count, 16)
    gradientProgram.setInt("numColorStops", value: Int32(numStops))

    for i in 0..<numStops {
      let stop = gradient.colorStops[i]
      gradientProgram.setVec4(
        "colorStops[\(i)]", value: (stop.color.red, stop.color.green, stop.color.blue, stop.color.alpha))
      gradientProgram.setFloat("colorLocations[\(i)]", value: stop.location)
    }

    // Draw the triangles
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)

    // Cleanup
    glDeleteVertexArrays(1, &vao)
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
  }
}
