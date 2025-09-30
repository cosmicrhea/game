import Foundation
import GL
import GLMath
import STBTrueType

final class TextRenderer {
  private let font: TrueTypeFont
  private var atlas: GlyphAtlas?
  private let program: GLProgram

  init?(_ name: String, _ pixelHeight: Float? = nil) {
    guard let entry = FontLibrary.resolve(name: name) else { return nil }
    let resolvedPixelHeight = pixelHeight ?? entry.pixelSize.map(Float.init) ?? 16
    guard let font = TrueTypeFont(path: entry.url.path, pixelHeight: resolvedPixelHeight) else {
      return nil
    }
    self.font = font
    self.program = try! GLProgram("ui/text")
  }

  func draw(
    _ text: String, at origin: (x: Float, y: Float), windowSize: (w: Int32, h: Int32),
    color: (Float, Float, Float, Float) = (1, 1, 1, 1)
  ) {
    let neededCodepoints = Set(text.utf8.map { Int32($0) })
    let haveCodepoints: Set<Int32> =
      if let existingAtlas = atlas {
        Set(existingAtlas.glyphs.keys)
      } else {
        []
      }

    if atlas == nil || !haveCodepoints.isSuperset(of: neededCodepoints) {
      atlas = GlyphAtlas.build(for: text, font: font)
    }

    guard let atlas = atlas else { return }

    var verts: [Float] = []
    var indices: [UInt32] = []
    var penX = origin.x
    let baseline = font.getBaseline()

    let bytes = Array(text.utf8)
    for (idx, u8) in bytes.enumerated() {
      let cp = Int32(u8)

      // Compute advance up-front so that whitespace (e.g. space) still advances the pen
      let next = (idx + 1 < bytes.count) ? Int32(bytes[idx + 1]) : nil
      let glyphAdvance = font.getAdvance(for: cp, next: next)

      if let g = atlas.glyphs[cp] {
        let x0 = penX + Float(g.xoff)
        let y0 = origin.y + baseline + Float(g.yoff)
        let x1 = x0 + Float(g.w)
        let y1 = y0 + Float(g.h)

        let u0 = g.u0
        let v0 = g.v0
        let u1 = g.u1
        let v1 = g.v1

        let base = UInt32(verts.count / 4)
        verts += [
          x0, y0, u0, v0,
          x1, y0, u1, v0,
          x1, y1, u1, v1,
          x0, y1, u0, v1,
        ]
        indices += [base, base + 1, base + 2, base + 2, base + 3, base]
      }

      penX += glyphAdvance
    }

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)
    glBindVertexArray(vao)

    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(
      GL_ARRAY_BUFFER, verts.count * MemoryLayout<Float>.stride, verts,
      GL_DYNAMIC_DRAW)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices,
      GL_DYNAMIC_DRAW)

    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0))
    let uvOff = UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      uvOff)

    // ortho
    let w = Float(windowSize.w)
    let h = Float(windowSize.h)
    let mvp: [Float] = [
      2 / w, 0, 0, 0,
      0, 2 / h, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]

    // UI should render on top: no depth/cull interference
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))

    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    program.use()
    mvp.withUnsafeBufferPointer { buffer in
      program.setMat4("uMVP", value: buffer.baseAddress!)
    }
    program.setVec4("uColor", value: (color.0, color.1, color.2, color.3))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, atlas.texture)
    program.setInt("uAtlas", value: 0)

    // Ensure polygons are filled for text even if the app toggled wireframe
    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // restore state
    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }
}

// MARK: - Glyph and Atlas

private struct Glyph {
  let codepoint: Int32
  let w: Int32, h: Int32
  let xoff: Int32, yoff: Int32
  let advance: Float
  var u0: Float = 0, v0: Float = 0, u1: Float = 0, v1: Float = 0
  var atlasX: Int32 = 0, atlasY: Int32 = 0
}

private final class GlyphAtlas {
  let texture: GLuint
  let width: Int32, height: Int32
  var glyphs: [Int32: Glyph] = [:]

  init(pixels: [UInt8], width: Int32, height: Int32, glyphs: [Glyph]) {
    self.width = width
    self.height = height

    var tex: GLuint = 0
    glGenTextures(1, &tex)
    glBindTexture(GL_TEXTURE_2D, tex)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_RED,
      width, height, 0,
      GL_RED, GL_UNSIGNED_BYTE,
      pixels
    )
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    let swizzle: [GLint] = [GL_ONE, GL_ONE, GL_ONE, GL_RED]
    glTexParameteriv(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_RGBA, swizzle)

    self.texture = tex

    for g in glyphs {
      var gg = g
      gg.u0 = Float(gg.atlasX) / Float(width)
      gg.u1 = Float(gg.atlasX + gg.w) / Float(width)
      // Flip V here because glyph bitmaps are stored top-to-bottom but OpenGL's
      // texture coordinate origin is bottom-left.
      let vTop = Float(gg.atlasY) / Float(height)
      let vBottom = Float(gg.atlasY + gg.h) / Float(height)
      gg.v0 = 1.0 - vBottom
      gg.v1 = 1.0 - vTop
      self.glyphs[gg.codepoint] = gg
    }
  }

  deinit {
    var t = texture
    glDeleteTextures(1, &t)
  }

  static func build(for text: String, font: TrueTypeFont, padding: Int32 = 2) -> GlyphAtlas? {
    var codepoints: [Int32] = []
    var seen = Set<Int32>()
    for byte in text.utf8 {
      let codepoint = Int32(byte)
      if seen.insert(codepoint).inserted { codepoints.append(codepoint) }
    }

    var glyphs: [Glyph] = []
    var rowW: Int32 = 0
    var rowH: Int32 = 0
    for (i, codepoint) in codepoints.enumerated() {
      guard let g = font.getGlyphBitmap(for: codepoint) else { continue }
      let next = (i + 1 < codepoints.count) ? codepoints[i + 1] : nil
      let advance = font.getAdvance(for: codepoint, next: next)
      glyphs.append(
        Glyph(
          codepoint: codepoint,
          w: g.width, h: g.height,
          xoff: g.xoff, yoff: g.yoff,
          advance: advance
        )
      )
      rowW += g.width + padding
      rowH = max(rowH, g.height)
    }
    if glyphs.isEmpty { return nil }

    let atlasW = max(64, rowW)
    let atlasH = max(64, rowH)
    var pixels = [UInt8](repeating: 0, count: Int(atlasW * atlasH))

    var cursorX: Int32 = 0
    for i in 0..<glyphs.count {
      let codepoint = glyphs[i].codepoint
      guard let glyphBitmap = font.getGlyphBitmap(for: codepoint) else { continue }
      for y in 0..<glyphBitmap.height {
        let dstRow = Int(y * atlasW + cursorX)
        let srcRow = Int(y * glyphBitmap.width)
        memcpy(
          &pixels[dstRow],
          glyphBitmap.pixels[srcRow...].withUnsafeBufferPointer { $0.baseAddress },
          Int(glyphBitmap.width)
        )
      }
      var g = glyphs[i]
      g.atlasX = cursorX
      g.atlasY = 0
      glyphs[i] = g
      cursorX += glyphBitmap.width + padding
    }

    return GlyphAtlas(pixels: pixels, width: atlasW, height: atlasH, glyphs: glyphs)
  }
}
