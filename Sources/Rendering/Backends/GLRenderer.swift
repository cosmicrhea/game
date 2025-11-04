public final class GLRenderer: Renderer {
  private let imageProgram: GLProgram
  private let pathProgram: GLProgram
  private let textProgram: GLProgram
  private let fboProgram: GLProgram
  private let gradientProgram: GLProgram
  private let debug3dProgram: GLProgram

  // Clear color state
  //private var clearColor = Color(0.2, 0.1, 0.1, 1.0)
  private var clearColor = Color.black

  // Viewport state
  private var _viewportSize: Size = DESIGN_RESOLUTION
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
    self.debug3dProgram = try! GLProgram("Common/debug3d", "Common/debug3d")

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
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
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

      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, GLuint(textureID))
      imageProgram.setInt("uTexture", value: 0)

      // Draw stroke outline if specified (similar to text stroke)
      if strokeWidth > 0, let strokeColor = strokeColor {
        imageProgram.setVec4(
          "uTint",
          value: (strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha))

        // Draw image at multiple offsets to create outline effect
        let offsets: [(Float, Float)] = [
          (-strokeWidth, 0), (strokeWidth, 0),
          (0, -strokeWidth), (0, strokeWidth),
          (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
          (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
        ]

        for (offsetX, offsetY) in offsets {
          var offsetVerts = verts
          for i in stride(from: 0, to: offsetVerts.count, by: 4) {
            offsetVerts[i] += offsetX
            offsetVerts[i + 1] += offsetY
          }

          glBindBuffer(GL_ARRAY_BUFFER, vbo)
          glBufferData(
            GL_ARRAY_BUFFER, offsetVerts.count * MemoryLayout<Float>.stride, offsetVerts,
            GL_DYNAMIC_DRAW)

          glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
        }
      }

      // Draw fill
      let tintColor = tint ?? .white
      imageProgram.setVec4("uTint", value: (tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha))

      glBindBuffer(GL_ARRAY_BUFFER, vbo)
      glBufferData(GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts, GL_DYNAMIC_DRAW)

      glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

  public func drawImageTransformed(
    textureID: UInt64,
    in rect: Rect,
    rotation: Float,
    scale: Point,
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
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

    // Compute rotated quad on CPU around center in pixel space
    let cx = x + w * 0.5
    let cy = y + h * 0.5
    let hw = (w * scale.x) * 0.5
    let hh = (h * scale.y) * 0.5
    let c = cos(rotation)
    let s = sin(rotation)

    func rot(_ px: Float, _ py: Float) -> (Float, Float) {
      // rotate (px,py) around origin then translate to center
      let rx = px * c - py * s
      let ry = px * s + py * c
      return (cx + rx, cy + ry)
    }

    // corners relative to center (counter-clockwise starting bottom-left to match UVs)
    let bl = rot(-hw, -hh)
    let br = rot(hw, -hh)
    let tr = rot(hw, hh)
    let tl = rot(-hw, hh)

    // Interleaved vertices x,y,u,v
    let verts: [Float] = [
      bl.0, bl.1, 0, 0,
      br.0, br.1, 1, 0,
      tr.0, tr.1, 1, 1,
      tl.0, tl.1, 0, 1,
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

    Self.withUIContext {
      imageProgram.use()
      // Use standard orthographic MVP mapping pixel positions to clip space
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
      mvp.withUnsafeBufferPointer { buf in imageProgram.setMat4("uMVP", value: buf.baseAddress!) }

      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, GLuint(textureID))
      imageProgram.setInt("uTexture", value: 0)

      // Draw stroke outline if specified
      if strokeWidth > 0, let strokeColor = strokeColor {
        imageProgram.setVec4(
          "uTint",
          value: (strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha))

        // For rotated images, apply stroke offsets in the rotated coordinate space
        let offsets: [(Float, Float)] = [
          (-strokeWidth, 0), (strokeWidth, 0),
          (0, -strokeWidth), (0, strokeWidth),
          (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
          (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
        ]

        // Rotate offset vectors
        let c = cos(rotation)
        let s = sin(rotation)
        func rotOffset(_ offsetX: Float, _ offsetY: Float) -> (Float, Float) {
          let rx = offsetX * c - offsetY * s
          let ry = offsetX * s + offsetY * c
          return (rx, ry)
        }

        for (offsetX, offsetY) in offsets {
          let (rotX, rotY) = rotOffset(offsetX, offsetY)
          var offsetVerts = verts
          for i in stride(from: 0, to: offsetVerts.count, by: 4) {
            offsetVerts[i] += rotX
            offsetVerts[i + 1] += rotY
          }

          glBindBuffer(GL_ARRAY_BUFFER, vbo)
          glBufferData(
            GL_ARRAY_BUFFER, offsetVerts.count * MemoryLayout<Float>.stride, offsetVerts,
            GL_DYNAMIC_DRAW)

          glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
        }
      }

      // Draw fill
      let tintColor = tint ?? .white
      imageProgram.setVec4("uTint", value: (tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha))

      glBindBuffer(GL_ARRAY_BUFFER, vbo)
      glBufferData(GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts, GL_DYNAMIC_DRAW)

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
    tint: Color?,
    strokeWidth: Float,
    strokeColor: Color?
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

      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, GLuint(textureID))
      imageProgram.setInt("uTexture", value: 0)

      // Draw stroke outline if specified
      if strokeWidth > 0, let strokeColor = strokeColor {
        imageProgram.setVec4(
          "uTint",
          value: (strokeColor.red, strokeColor.green, strokeColor.blue, strokeColor.alpha))

        // Draw image at multiple offsets to create outline effect
        let offsets: [(Float, Float)] = [
          (-strokeWidth, 0), (strokeWidth, 0),
          (0, -strokeWidth), (0, strokeWidth),
          (-strokeWidth, -strokeWidth), (strokeWidth, strokeWidth),
          (-strokeWidth, strokeWidth), (strokeWidth, -strokeWidth),
        ]

        for (offsetX, offsetY) in offsets {
          var offsetVerts = verts
          for i in stride(from: 0, to: offsetVerts.count, by: 4) {
            offsetVerts[i] += offsetX
            offsetVerts[i + 1] += offsetY
          }

          glBindBuffer(GL_ARRAY_BUFFER, vbo)
          glBufferData(
            GL_ARRAY_BUFFER, offsetVerts.count * MemoryLayout<Float>.stride, offsetVerts,
            GL_DYNAMIC_DRAW)

          glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
        }
      }

      // Draw fill
      let tintColor = tint ?? .white
      imageProgram.setVec4("uTint", value: (tintColor.red, tintColor.green, tintColor.blue, tintColor.alpha))

      glBindBuffer(GL_ARRAY_BUFFER, vbo)
      glBufferData(GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts, GL_DYNAMIC_DRAW)

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
    anchor: AnchorPoint = .topLeft,
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
    let features = Font.Features(monospaceDigits: defaultStyle.monospaceDigits)
    guard let font = Font(fontName: defaultStyle.fontName, pixelHeight: defaultStyle.fontSize, features: features)
    else {
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

    // Convert AnchorPoint to anchor offset
    let anchorOffset = calculateAnchorOffset(
      layoutResult: layoutResult,
      origin: finalOrigin,
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
      let lineBaselineY = finalOrigin.y + anchorOffset.y - Float(line.baselineY) * lineHeight

      // Calculate X offset based on text alignment (not positioning alignment)
      let lineXOffset: Float
      if let wrapWidth = wrapWidth {
        switch textAlignment {
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
    withUIContext {
      drawGradientTriangles(
        gradient, vertices: vertices, indices: indices, type: 0, angle: angle, center: nil, bounds: bounds)
    }
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

  private func calculateAnchorOffset(
    layoutResult: TextLayout.LayoutResult,
    origin: Point,
    anchor: AnchorPoint,
    scale: Float,
    font: Font
  ) -> Point {
    // Use the same approach as the working ModularTextRenderer
    let baseline = font.baselineFromTop * scale

    switch anchor {
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
      let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil

      // Handle spaces - they should advance but not render
      if codepoint == 32 {  // Space character
        // Advance using Font-level advance so features & kerning apply
        let adv = font.getAdvance(for: codepoint, next: next, scale: 1.0)
        currentX += adv * scale
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

      // Advance to next character using Font-level advance (includes features and kerning)
      let adv = font.getAdvance(for: codepoint, next: next, scale: 1.0)
      currentX += adv * scale
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

  /// Adopt the color texture from a framebuffer, removing the FBO and returning the texture ID.
  /// The framebuffer object and its depth buffer are deleted; the texture persists for the caller.
  public func adoptTexture(from framebufferID: UInt64) -> UInt64? {
    guard let framebuffer = framebuffers.removeValue(forKey: framebufferID) else { return nil }
    let tex = framebuffer.detachTexture()
    return tex
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

  // MARK: - 3D Debug Drawing

  /// Draw a 3D debug arrow in world space
  /// - Parameters:
  ///   - from: Start position of the arrow
  ///   - to: End position of the arrow
  ///   - color: Color of the arrow
  ///   - projection: Camera projection matrix
  ///   - view: Camera view matrix
  ///   - headLength: Length of the arrowhead (default: 10% of total length)
  ///   - headRadius: Radius of the arrowhead base (default: 3% of total length)
  ///   - lineThickness: Thickness of the lines (default: 0.01)
  ///   - depthTest: Whether to enable depth testing (default: true)
  public func drawDebugArrow3D(
    from: vec3,
    to: vec3,
    color: Color,
    projection: mat4,
    view: mat4,
    headLength: Float? = nil,
    headRadius: Float? = nil,
    lineThickness: Float = 1.0,
    depthTest: Bool = true
  ) {
    let direction = to - from
    let arrowLength = length(direction)

    guard arrowLength > 0.001 else { return }  // Don't draw degenerate arrows

    let normalizedDirection = normalize(direction)

    // Calculate shaft radius from lineThickness
    let baseShaftRadius = arrowLength * 0.01
    let actualShaftRadius = baseShaftRadius * lineThickness
    let actualHeadRadius = (headRadius ?? (arrowLength * 0.03)) * lineThickness

    // Generate volumetric arrow geometry (proper 3D mesh, not wireframe)
    let (volumetricVertices, volumetricIndices) = ArrowGeometryGenerator.generateArrow(
      length: arrowLength,
      headLength: headLength,
      headRadius: actualHeadRadius,
      shaftRadius: actualShaftRadius,
      segments: 8
    )

    // Transform arrow geometry from local space (+Z axis) to world space
    // Arrow points along +Z axis in local space, need to align with direction vector
    let zAxis = vec3(0, 0, 1)
    let dotProduct = dot(zAxis, normalizedDirection)

    // Build model matrix: translate to start, then rotate to direction
    var modelMatrix = mat4(1)
    modelMatrix = GLMath.translate(modelMatrix, from)

    // Handle rotation - check if direction is already aligned with +Z
    if abs(dotProduct - 1.0) > 0.001 {
      // Check if direction is opposite to +Z (special case)
      if abs(dotProduct + 1.0) < 0.001 {
        // 180 degree rotation around any perpendicular axis
        modelMatrix = GLMath.rotate(modelMatrix, Float.pi, vec3(1, 0, 0))
      } else {
        // General rotation
        let rotationAxis = cross(zAxis, normalizedDirection)
        if length(rotationAxis) > 0.001 {
          let normalizedAxis = normalize(rotationAxis)
          let rotationAngle = acos(max(-1.0, min(1.0, dotProduct)))
          modelMatrix = GLMath.rotate(modelMatrix, rotationAngle, normalizedAxis)
        }
      }
    }

    // Volumetric vertices format: [pos(3), normal(3), uv(2), tangent(3), bitangent(3)] = 14 floats per vertex
    let floatsPerVertex = 14
    let vertexCount = volumetricVertices.count / floatsPerVertex

    // Transform vertices and extract position + color
    var interleavedData: [Float] = []
    interleavedData.reserveCapacity(vertexCount * 6)  // pos(3) + color(3)

    for i in 0..<vertexCount {
      let baseIndex = i * floatsPerVertex

      // Extract position from volumetric vertex data
      let localPos = vec3(
        volumetricVertices[baseIndex + 0],
        volumetricVertices[baseIndex + 1],
        volumetricVertices[baseIndex + 2]
      )

      // Transform position by model matrix
      let worldPos = modelMatrix * vec4(localPos.x, localPos.y, localPos.z, 1.0)

      // Add transformed position
      interleavedData.append(worldPos.x)
      interleavedData.append(worldPos.y)
      interleavedData.append(worldPos.z)

      // Add color
      interleavedData.append(color.red)
      interleavedData.append(color.green)
      interleavedData.append(color.blue)
    }

    // Create VAO/VBO/EBO
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
      interleavedData.count * MemoryLayout<Float>.stride,
      interleavedData,
      GL_DYNAMIC_DRAW
    )

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    volumetricIndices.withUnsafeBytes { bytes in
      glBufferData(
        GL_ELEMENT_ARRAY_BUFFER,
        bytes.count,
        bytes.baseAddress,
        GL_DYNAMIC_DRAW
      )
    }

    // Position attribute (location 0)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 3, GL_FLOAT, false,
      GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0)
    )

    // Color attribute (location 1)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 3, GL_FLOAT, false,
      GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 3 * MemoryLayout<Float>.stride)
    )

    // Set up 3D rendering state (depth testing optionally enabled, no face culling for lines)
    let wasDepthEnabled = glIsEnabled(GL_DEPTH_TEST)
    let wasCullEnabled = glIsEnabled(GL_CULL_FACE)

    if depthTest {
      glEnable(GL_DEPTH_TEST)
    } else {
      glDisable(GL_DEPTH_TEST)
    }
    glDisable(GL_CULL_FACE)

    // Use debug3d shader
    debug3dProgram.use()

    // Set identity model matrix (vertices already transformed)
    let identityModel = mat4(1)
    debug3dProgram.setMat4("model", value: identityModel)
    debug3dProgram.setMat4("view", value: view)
    debug3dProgram.setMat4("projection", value: projection)

    // Draw triangles (volumetric mesh, not lines)
    glBindVertexArray(vao)
    glDrawElements(
      GL_TRIANGLES,
      GLsizei(volumetricIndices.count),
      GL_UNSIGNED_INT,
      nil
    )
    glBindVertexArray(0)

    // Restore state
    if wasDepthEnabled {
      glEnable(GL_DEPTH_TEST)
    } else {
      glDisable(GL_DEPTH_TEST)
    }
    if wasCullEnabled {
      glEnable(GL_CULL_FACE)
    }

    // Cleanup
    glDeleteVertexArrays(1, &vao)
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
  }

  /// Draw a simple 3D line between two points in world space
  /// - Parameters:
  ///   - from: Start position of the line
  ///   - to: End position of the line
  ///   - color: Color of the line
  ///   - projection: Camera projection matrix
  ///   - view: Camera view matrix
  ///   - lineThickness: Thickness of the line (default: 0.01)
  ///   - depthTest: Whether to enable depth testing (default: false for wireframe overlay)
  public func drawDebugLine3D(
    from: vec3,
    to: vec3,
    color: Color,
    projection: mat4,
    view: mat4,
    lineThickness: Float = 0.01,
    depthTest: Bool = false
  ) {
    let direction = to - from
    let lineLength = length(direction)

    guard lineLength > 0.001 else { return }  // Don't draw degenerate lines

    // Simple cylinder for line segment (just a thin box aligned with direction)
    let normalizedDirection = normalize(direction)
    let halfThickness = lineThickness * 0.5

    // Generate simple box geometry aligned with direction
    // Use a simple cross-section: 4 vertices forming a square perpendicular to direction
    let perpendicular =
      abs(normalizedDirection.y) < 0.9
      ? normalize(cross(normalizedDirection, vec3(0, 1, 0)))
      : normalize(cross(normalizedDirection, vec3(1, 0, 0)))
    let perpendicular2 = normalize(cross(normalizedDirection, perpendicular))

    // Generate 8 vertices for a box (2 cross-sections, 4 vertices each)
    var vertices: [Float] = []
    //var indices: [UInt32] = []

    // First cross-section at 'from'
    let offset1 = perpendicular * halfThickness + perpendicular2 * halfThickness
    let offset2 = perpendicular * halfThickness - perpendicular2 * halfThickness
    let offset3 = -perpendicular * halfThickness - perpendicular2 * halfThickness
    let offset4 = -perpendicular * halfThickness + perpendicular2 * halfThickness

    vertices.append(contentsOf: [from.x + offset1.x, from.y + offset1.y, from.z + offset1.z])
    vertices.append(contentsOf: [from.x + offset2.x, from.y + offset2.y, from.z + offset2.z])
    vertices.append(contentsOf: [from.x + offset3.x, from.y + offset3.y, from.z + offset3.z])
    vertices.append(contentsOf: [from.x + offset4.x, from.y + offset4.y, from.z + offset4.z])

    // Second cross-section at 'to'
    vertices.append(contentsOf: [to.x + offset1.x, to.y + offset1.y, to.z + offset1.z])
    vertices.append(contentsOf: [to.x + offset2.x, to.y + offset2.y, to.z + offset2.z])
    vertices.append(contentsOf: [to.x + offset3.x, to.y + offset3.y, to.z + offset3.z])
    vertices.append(contentsOf: [to.x + offset4.x, to.y + offset4.y, to.z + offset4.z])

    // Generate indices for box faces (6 faces, 2 triangles each = 12 triangles = 36 indices)
    // But for wireframe, we only need edges: 12 edges, 2 vertices each = 24 indices
    // Actually, for simple lines we can just draw a thin cylinder
    // Let's use a simpler approach: just draw the 4 edges connecting the two cross-sections
    let edgeIndices: [UInt32] = [
      // Connect corresponding vertices between cross-sections
      0, 4, 1, 5, 2, 6, 3, 7,
      // Connect vertices within each cross-section
      0, 1, 1, 2, 2, 3, 3, 0,
      4, 5, 5, 6, 6, 7, 7, 4,
    ]

    // Interleave with color data
    var interleavedData: [Float] = []
    interleavedData.reserveCapacity(vertices.count / 3 * 6)  // pos(3) + color(3)

    for i in 0..<(vertices.count / 3) {
      let baseIndex = i * 3
      interleavedData.append(vertices[baseIndex + 0])
      interleavedData.append(vertices[baseIndex + 1])
      interleavedData.append(vertices[baseIndex + 2])
      interleavedData.append(color.red)
      interleavedData.append(color.green)
      interleavedData.append(color.blue)
    }

    // Create VAO, VBO, EBO
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
      interleavedData.count * MemoryLayout<Float>.stride,
      interleavedData,
      GL_DYNAMIC_DRAW
    )

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    edgeIndices.withUnsafeBytes { bytes in
      glBufferData(
        GL_ELEMENT_ARRAY_BUFFER,
        bytes.count,
        bytes.baseAddress,
        GL_DYNAMIC_DRAW
      )
    }

    // Position attribute (location 0)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 3, GL_FLOAT, false,
      GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0)
    )

    // Color attribute (location 1)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 3, GL_FLOAT, false,
      GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 3 * MemoryLayout<Float>.stride)
    )

    // Set up 3D rendering state
    let wasDepthEnabled = glIsEnabled(GL_DEPTH_TEST)
    let wasCullEnabled = glIsEnabled(GL_CULL_FACE)

    if depthTest {
      glEnable(GL_DEPTH_TEST)
    } else {
      glDisable(GL_DEPTH_TEST)
    }
    glDisable(GL_CULL_FACE)

    // Use debug3d shader
    debug3dProgram.use()

    // Set identity model matrix (vertices already in world space)
    let identityModel = mat4(1)
    debug3dProgram.setMat4("model", value: identityModel)
    debug3dProgram.setMat4("view", value: view)
    debug3dProgram.setMat4("projection", value: projection)

    // Draw as lines
    glBindVertexArray(vao)
    glDrawElements(
      GL_LINES,
      GLsizei(edgeIndices.count),
      GL_UNSIGNED_INT,
      nil
    )
    glBindVertexArray(0)

    // Restore state
    if wasDepthEnabled {
      glEnable(GL_DEPTH_TEST)
    } else {
      glDisable(GL_DEPTH_TEST)
    }
    if wasCullEnabled {
      glEnable(GL_CULL_FACE)
    }

    // Cleanup
    glDeleteVertexArrays(1, &vao)
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
  }
}
