import Foundation
import GL
import GLMath
import STBTrueType

/// Simplified text renderer using modular components
public final class ModularTextRenderer {
  private let font: Font
  private let layout: TextLayout
  private let program: GLProgram
  private var atlas: GlyphAtlas?

  /// Global scale factor applied at draw time
  public var scale: Float = 1.0

  public enum Anchor {
    case topLeft
    case bottomLeft
    case baselineLeft
  }

  public init?(fontName: String, pixelHeight: Float? = nil) {
    guard let font = Font(fontName: fontName, pixelHeight: pixelHeight) else {
      return nil
    }

    self.font = font
    self.layout = TextLayout(font: font.getTrueTypeFont(), scale: 1.0)
    self.program = try! GLProgram("UI/text")
  }

  // MARK: - Public Properties

  /// Line height with current scale applied
  public var scaledLineHeight: Float {
    font.lineHeight * scale
  }

  /// Baseline offset from the top of the line box
  public var baselineFromTop: Float {
    font.baselineFromTop
  }

  /// Distance below the baseline to the deepest descender
  public var descentFromBaseline: Float {
    font.descentFromBaseline
  }

  // MARK: - Public Methods

  /// Measure the width of text at current scale
  public func measureWidth(_ text: String) -> Float {
    return font.measureWidth(text, scale: scale)
  }

  /// Draw plain text with optional wrapping and styling (legacy method)
  public func draw(
    _ text: String,
    at origin: (x: Float, y: Float),
    windowSize: (w: Int32, h: Int32),
    color: (Float, Float, Float, Float) = (1, 1, 1, 1),
    scale overrideScale: Float? = nil,
    wrapWidth: Float? = nil,
    anchor: Anchor = .topLeft,
    outlineColor: (Float, Float, Float, Float)? = nil,
    outlineThickness: Float = 0.0,
    shadowColor: (Float, Float, Float, Float)? = nil,
    shadowOffset: (x: Float, y: Float) = (0, 0),
    shadowBlur: Float = 0.0
  ) {
    let currentScale = overrideScale ?? self.scale
    let lineHeight = font.lineHeight * currentScale

    // Layout the text
    let layoutResult = layout.layout(
      text,
      wrapWidth: wrapWidth,
      lineHeight: lineHeight
    )

    // Ensure we have an atlas for the required glyphs
    ensureAtlas(for: text)
    guard let atlas = atlas else { return }

    // Calculate anchor offset
    let anchorOffset = calculateAnchorOffset(
      layoutResult: layoutResult,
      origin: origin,
      anchor: anchor,
      scale: currentScale
    )

    // Generate vertices for all lines
    var allVertices: [Float] = []
    var allIndices: [UInt32] = []
    var indexOffset: UInt32 = 0

    for line in layoutResult.lines {
      let lineVertices = generateLineVertices(
        line: line,
        atlas: atlas,
        origin: (origin.x + anchorOffset.x, origin.y + anchorOffset.y),
        scale: currentScale,
        color: color
      )

      let lineIndices = generateLineIndices(
        vertexCount: lineVertices.count / 8,  // 8 components: x, y, u, v, r, g, b, a
        indexOffset: indexOffset
      )

      allVertices.append(contentsOf: lineVertices)
      allIndices.append(contentsOf: lineIndices)
      indexOffset += UInt32(lineVertices.count / 8)
    }

    // Render the text
    renderVertices(
      allVertices,
      allIndices,
      atlas: atlas,
      color: color,
      outlineColor: outlineColor,
      outlineThickness: outlineThickness,
      shadowColor: shadowColor,
      shadowOffset: shadowOffset,
      shadowBlur: shadowBlur,
      windowSize: windowSize
    )
  }

  // MARK: - Private Methods

  private func ensureAtlas(for text: String) {
    let neededCodepoints = Set(text.utf8.map { Int32($0) })
    let haveCodepoints: Set<Int32>
    if let atlas = atlas {
      haveCodepoints = Set(atlas.glyphs.keys)
    } else {
      haveCodepoints = Set<Int32>()
    }

    if atlas == nil || !haveCodepoints.isSuperset(of: neededCodepoints) {
      atlas = GlyphAtlas.build(for: text, font: font.getTrueTypeFont())
    }
  }

  private func calculateAnchorOffset(
    layoutResult: TextLayout.LayoutResult,
    origin: (x: Float, y: Float),
    anchor: Anchor,
    scale: Float
  ) -> (x: Float, y: Float) {
    let baseline = font.baselineFromTop * scale

    switch anchor {
    case .topLeft:
      return (0, -baseline)
    case .bottomLeft:
      return (0, layoutResult.totalHeight - layoutResult.lineHeight - baseline)
    case .baselineLeft:
      return (0, 0)
    }
  }

  private func generateLineVertices(
    line: TextLayout.Line,
    atlas: GlyphAtlas,
    origin: (x: Float, y: Float),
    scale: Float,
    color: (Float, Float, Float, Float) = (1, 1, 1, 1)
  ) -> [Float] {
    var vertices: [Float] = []
    var penX = origin.x
    let lineBaselineY = origin.y - Float(line.baselineY) * font.lineHeight * scale

    // Process Unicode scalars instead of UTF-8 bytes
    let scalars = Array(line.text.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let codepoint = Int32(scalars[i].value)
      let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil

      if let glyph = atlas.glyphs[codepoint] {
        let x0 = penX + Float(glyph.xOffset) * scale
        let y1 = lineBaselineY - Float(glyph.yOffset) * scale
        let y0 = y1 - Float(glyph.height) * scale
        let x1 = x0 + Float(glyph.width) * scale

        vertices += [
          x0, y0, glyph.u0, glyph.v0, color.0, color.1, color.2, color.3,  // bottom-left
          x1, y0, glyph.u1, glyph.v0, color.0, color.1, color.2, color.3,  // bottom-right
          x1, y1, glyph.u1, glyph.v1, color.0, color.1, color.2, color.3,  // top-right
          x0, y1, glyph.u0, glyph.v1, color.0, color.1, color.2, color.3,  // top-left
        ]
      }

      penX += font.getAdvance(for: codepoint, next: next, scale: scale)
      i += 1
    }

    return vertices
  }

  private func generateLineIndices(vertexCount: Int, indexOffset: UInt32) -> [UInt32] {
    var indices: [UInt32] = []
    let quadCount = vertexCount / 4

    for i in 0..<quadCount {
      let base = indexOffset + UInt32(i * 4)
      indices += [
        base, base + 1, base + 2,  // first triangle
        base + 2, base + 3, base,  // second triangle
      ]
    }

    return indices
  }

  private func renderVertices(
    _ vertices: [Float],
    _ indices: [UInt32],
    atlas: GlyphAtlas,
    color: (Float, Float, Float, Float),
    outlineColor: (Float, Float, Float, Float)?,
    outlineThickness: Float,
    shadowColor: (Float, Float, Float, Float)?,
    shadowOffset: (x: Float, y: Float),
    shadowBlur: Float,
    windowSize: (w: Int32, h: Int32)
  ) {
    // Create OpenGL objects
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

    // Set up vertex attributes (x, y, u, v, r, g, b, a)
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

    // Save and set render state
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(false)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    program.use()
    mvp.withUnsafeBufferPointer { buffer in
      program.setMat4("uMVP", value: buffer.baseAddress!)
    }

    // Draw shadow first if specified
    if let shadowColor = shadowColor, shadowBlur > 0 {
      program.setVec4("uColor", value: (shadowColor.0, shadowColor.1, shadowColor.2, shadowColor.3))

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
      program.setInt("uAtlas", value: 0)

      glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    }

    // Draw outline if specified
    if let outlineColor = outlineColor, outlineThickness > 0 {
      program.setVec4("uColor", value: (outlineColor.0, outlineColor.1, outlineColor.2, outlineColor.3))

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
        program.setInt("uAtlas", value: 0)

        glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
      }
    }

    // Draw fill
    program.setVec4("uColor", value: (color.0, color.1, color.2, color.3))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, atlas.texture)
    program.setInt("uAtlas", value: 0)

    // Ensure filled polygons
    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_DYNAMIC_DRAW)

    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)

    // Restore state
    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(true)
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    // Clean up
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }

}
