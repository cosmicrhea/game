import Foundation
import GL
import STBTrueType

public final class GLRenderer: Renderer {
  private let imageProgram: GLProgram
  private let pathProgram: GLProgram
  private let textProgram: GLProgram

  // Clear color state
  private var clearColor = Color(0.2, 0.1, 0.1, 1.0)

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
    self.imageProgram = try! GLProgram("UI/text", "UI/image")
    self.pathProgram = try! GLProgram("Common/path", "Common/path")
    self.textProgram = try! GLProgram("UI/text")

    // Enable depth testing
    glEnable(GL_DEPTH_TEST)

    // Enable MSAA for antialiasing - this handles all antialiasing automatically
    glEnable(GL_MULTISAMPLE)
  }

  public func beginFrame(viewportSize: Size, scale: Float) {
    glViewport(0, 0, GLsizei(viewportSize.width), GLsizei(viewportSize.height))

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
    anchor: TextAnchor = .topLeft,
    alignment: TextAlignment = .left
  ) {
    // Create font and layout for the default style
    guard let font = Font(fontName: defaultStyle.fontName, pixelHeight: defaultStyle.fontSize) else {
      return
    }

    let layout = TextLayout(font: font.getTrueTypeFont(), scale: 1.0)

    // Get current viewport size from OpenGL
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)
    let windowSize = (w: Int32(viewport[2]), h: Int32(viewport[3]))

    let text = attributedString.string
    let currentScale: Float = 1.0
    let lineHeight = font.lineHeight * currentScale

    // Layout the text
    let layoutResult = layout.layout(
      text,
      wrapWidth: wrapWidth,
      lineHeight: lineHeight
    )

    // Ensure we have an atlas for the required glyphs
    guard let atlas = GlyphAtlas.build(for: text, font: font.getTrueTypeFont()) else { return }

    // Convert TextAnchor to anchor offset
    let anchorOffset = calculateTextAnchorOffset(
      layoutResult: layoutResult,
      origin: origin,
      anchor: anchor,
      scale: currentScale,
      font: font
    )

    // Generate vertices for all lines
    var allVertices: [Float] = []
    var allIndices: [UInt32] = []
    var indexOffset: UInt32 = 0

    for (_, line) in layoutResult.lines.enumerated() {
      // Calculate proper Y position for this line using the working approach
      let lineBaselineY = origin.y + anchorOffset.y - Float(line.baselineY) * lineHeight

      // Calculate X offset based on alignment
      let lineXOffset: Float
      if let wrapWidth = wrapWidth {
        switch alignment {
        case .left:
          lineXOffset = 0
        case .center:
          lineXOffset = (wrapWidth - line.width) / 2
        case .right:
          lineXOffset = wrapWidth - line.width
        }
      } else {
        lineXOffset = 0
      }

      let lineVertices = generateTextLineVertices(
        line: line,
        atlas: atlas,
        origin: Point(origin.x + anchorOffset.x + lineXOffset, lineBaselineY),
        scale: currentScale,
        color: defaultStyle.color
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
    Self.withUIContext {
      pathProgram.use()
      glBindVertexArray(vao)
      glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  // MARK: - Text Rendering Helpers

  private func calculateTextAnchorOffset(
    layoutResult: TextLayout.LayoutResult,
    origin: Point,
    anchor: TextAnchor,
    scale: Float,
    font: Font
  ) -> Point {
    // Use the same approach as the working ModularTextRenderer
    let baseline = font.baselineFromTop * scale

    switch anchor {
    case .topLeft:
      return Point(0, -baseline)
    case .bottomLeft:
      return Point(0, layoutResult.totalHeight - baseline)
    case .baselineLeft:
      return Point(0, 0)
    }
  }

  private func generateTextLineVertices(
    line: TextLayout.Line,
    atlas: GlyphAtlas,
    origin: Point,
    scale: Float,
    color: Color
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
        // Use a reasonable space width if not in atlas
        let spaceWidth = atlas.glyphs[32]?.advance ?? 8  // Default space width
        currentX += Float(spaceWidth) * scale
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
}
