import Foundation
import GL
import GLMath
import STBTrueType

final class TextRenderer {
  private let font: TrueTypeFont
  private var atlas: GlyphAtlas?
  private let program: GLProgram
  private let maxAboveBaseline: Float
  private let maxBelowBaseline: Float
  private let baselinePx: Float
  /// Global scale factor applied at draw time (acts like em scale)
  var scale: Float = 1.0

  enum Anchor {
    case topLeft
    case bottomLeft
    case baselineLeft
  }

  init?(_ name: String, _ pixelHeight: Float? = nil) {
    guard let entry = FontLibrary.resolve(name: name) else { return nil }
    let resolvedPixelHeight = pixelHeight ?? entry.pixelSize.map(Float.init) ?? 16
    guard let font = TrueTypeFont(path: entry.url.path, pixelHeight: resolvedPixelHeight) else {
      return nil
    }
    self.font = font
    self.program = try! GLProgram("UI/text")

    // Precompute conservative line metrics by scanning a representative ASCII range.
    var above: Float = 0
    var below: Float = 0
    for cp in 32...126 {
      if let g = font.getGlyphBitmap(for: Int32(cp)) {
        let gAbove = max(0, -Float(g.yoff))
        let gBelow = max(0, Float(g.yoff + g.height))
        above = max(above, gAbove)
        below = max(below, gBelow)
      }
    }
    self.maxAboveBaseline = above
    self.maxBelowBaseline = below
    self.baselinePx = font.getBaseline()
  }

  /// Pixel height to move the pen between lines.
  /// Calculated as distance from highest ascender to lowest descender encountered.
  // Use a conservative ascent that accounts for glyphs exceeding the font ascender,
  // then add the maximum descender depth we observed.
  var lineHeight: Float { baselineFromTop + maxBelowBaseline }
  /// Line height with `scale` applied
  var scaledLineHeight: Float { lineHeight * scale }

  /// Baseline offset from the top of the line box (useful for aligning mixed sizes).
  var baselineFromTop: Float { baselinePx }

  /// Distance below the baseline to the deepest descender encountered.
  var descentFromBaseline: Float { maxBelowBaseline }

  func draw(
    _ text: String, at origin: (x: Float, y: Float), windowSize: (w: Int32, h: Int32),
    color: (Float, Float, Float, Float) = (1, 1, 1, 1),
    scale overrideScale: Float? = nil,
    wrapWidth: Float? = nil,
    anchor: Anchor = .topLeft
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

    let s = overrideScale ?? self.scale
    var verts: [Float] = []
    var indices: [UInt32] = []

    // Layout state
    var penX = origin.x
    var lineIndex: Int = 0
    let baseline = font.getBaseline() * s
    let scaledLineHeight =
      self.scaledLineHeight * (overrideScale != nil ? (overrideScale! / self.scale) : 1)

    // Helpers
    @inline(__always) func remainingWidth() -> Float? {
      guard let wrap = wrapWidth else { return nil }
      return wrap - (penX - origin.x)
    }
    @inline(__always) func advanceFor(_ cp: Int32, _ next: Int32?) -> Float {
      return font.getAdvance(for: cp, next: next) * s
    }

    let bytes = Array(text.utf8)

    enum TokKind { case word, space, newline }
    struct Tok {
      let kind: TokKind
      let start: Int
      let end: Int
    }

    // Tokenize into words, spaces/tabs, and newlines (handling CRLF)
    var tokens: [Tok] = []
    var i = 0
    while i < bytes.count {
      let b = bytes[i]
      if b == 10 || b == 13 {  // \n or \r
        // Coalesce CRLF into a single newline
        if b == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 { i += 1 }
        tokens.append(Tok(kind: .newline, start: i, end: i + 1))
        i += 1
        continue
      }
      let isSpace = (b == 32) || (b == 9)  // space or tab
      let kind: TokKind = isSpace ? .space : .word
      let start = i
      while i < bytes.count {
        let bb = bytes[i]
        if bb == 10 || bb == 13 { break }
        let ws = (bb == 32) || (bb == 9)
        if ws != isSpace { break }
        i += 1
      }
      tokens.append(Tok(kind: kind, start: start, end: i))
    }

    func tokenWidth(_ tok: Tok) -> Float {
      switch tok.kind {
      case .newline:
        return 0
      case .space:
        var width: Float = 0
        var j = tok.start
        while j < tok.end {
          let b = bytes[j]
          if b == 9 {  // tab -> 4 spaces
            let sp: Int32 = 32
            let adv = advanceFor(sp, sp)
            width += adv * 4
          } else {
            let cp = Int32(b)
            let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
            width += advanceFor(cp, next)
          }
          j += 1
        }
        return width
      case .word:
        var width: Float = 0
        var j = tok.start
        while j < tok.end {
          let cp = Int32(bytes[j])
          let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
          width += advanceFor(cp, next)
          j += 1
        }
        return width
      }
    }

    // Measurement pre-pass to compute line count and max width for anchoring
    func measureLines() -> (Int, Float) {
      var localPenX = origin.x
      var localLineIndex = 0
      var maxWidth: Float = 0
      var t = 0
      while t < tokens.count {
        let tok = tokens[t]
        if tok.kind == .newline {
          maxWidth = max(maxWidth, localPenX - origin.x)
          localLineIndex += 1
          localPenX = origin.x
          t += 1
          continue
        }
        let tWidth = tokenWidth(tok)
        if let wrap = wrapWidth {
          let remain = wrap - (localPenX - origin.x)
          if tWidth > remain && localPenX > origin.x && tok.kind != .space {
            maxWidth = max(maxWidth, localPenX - origin.x)
            localLineIndex += 1
            localPenX = origin.x
            continue
          }
        }
        switch tok.kind {
        case .space:
          var j = tok.start
          while j < tok.end {
            let b = bytes[j]
            let adv: Float
            if b == 9 {
              let sp: Int32 = 32
              adv = advanceFor(sp, sp) * 4
            } else {
              let cp = Int32(b)
              let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
              adv = advanceFor(cp, next)
            }
            if let wrap = wrapWidth {
              let remain = wrap - (localPenX - origin.x)
              if adv > remain && localPenX > origin.x {
                maxWidth = max(maxWidth, localPenX - origin.x)
                localLineIndex += 1
                localPenX = origin.x
              }
            }
            localPenX += adv
            j += 1
          }
        case .word:
          var j = tok.start
          while j < tok.end {
            let cp = Int32(bytes[j])
            let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
            let adv = advanceFor(cp, next)
            if let wrap = wrapWidth {
              let remain = wrap - (localPenX - origin.x)
              if adv > remain && localPenX > origin.x {
                maxWidth = max(maxWidth, localPenX - origin.x)
                localLineIndex += 1
                localPenX = origin.x
              }
            }
            localPenX += adv
            j += 1
          }
        case .newline:
          break
        }
        t += 1
      }
      maxWidth = max(maxWidth, localPenX - origin.x)
      return (localLineIndex + 1, maxWidth)
    }

    let (measuredLineCount, _) = measureLines()
    let totalHeight = Float(measuredLineCount) * scaledLineHeight
    let firstBaselineY: Float = {
      switch anchor {
      case .topLeft:
        return origin.y - baseline
      case .bottomLeft:
        return origin.y + totalHeight - scaledLineHeight - baseline
      case .baselineLeft:
        return origin.y
      }
    }()

    // (emit helper removed; emission happens inline using baseline maths)

    // Layout and draw
    var t = 0
    while t < tokens.count {
      let tok = tokens[t]
      if tok.kind == .newline {
        lineIndex += 1
        penX = origin.x
        t += 1
        continue
      }

      let tWidth = tokenWidth(tok)
      if let remain = remainingWidth() {
        if tWidth > remain && penX > origin.x && tok.kind != .space {
          // Move to next line and retry this token
          lineIndex += 1
          penX = origin.x
          continue
        }
      }

      switch tok.kind {
      case .space:
        var j = tok.start
        while j < tok.end {
          let b = bytes[j]
          if b == 9 {  // tab -> 4 spaces (advance only)
            let sp: Int32 = 32
            let adv = advanceFor(sp, sp) * 4
            if let remain = remainingWidth(), adv > remain && penX > origin.x {
              lineIndex += 1
              penX = origin.x
              continue
            }
            penX += adv
          } else {
            let cp = Int32(b)
            let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
            let adv = advanceFor(cp, next)
            if let remain = remainingWidth(), adv > remain && penX > origin.x {
              lineIndex += 1
              penX = origin.x
              continue
            }
            // Do not emit geometry for plain spaces; just advance
            penX += adv
          }
          j += 1
        }
      case .word:
        var j = tok.start
        while j < tok.end {
          let cp = Int32(bytes[j])
          let next: Int32? = (j + 1 < tok.end) ? Int32(bytes[j + 1]) : nil
          let adv = advanceFor(cp, next)
          if let remain = remainingWidth(), adv > remain && penX > origin.x {
            // Hard wrap inside a long word
            lineIndex += 1
            penX = origin.x
          }
          // Emit a single codepoint quad at current pen and baseline of this line
          if let g = atlas.glyphs[cp] {
            let lineBaselineY = firstBaselineY - Float(lineIndex) * scaledLineHeight
            let x0 = penX + Float(g.xoff) * s
            let y1 = lineBaselineY - Float(g.yoff) * s
            let y0 = y1 - Float(g.h) * s
            let x1 = x0 + Float(g.w) * s
            let base = UInt32(verts.count / 4)
            verts += [
              x0, y0, g.u0, g.v0,
              x1, y0, g.u1, g.v0,
              x1, y1, g.u1, g.v1,
              x0, y1, g.u0, g.v1,
            ]
            indices += [base, base + 1, base + 2, base + 2, base + 3, base]
          }
          penX += adv
          j += 1
        }
      case .newline:
        break
      }

      t += 1
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
