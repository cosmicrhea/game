import Foundation
import GL
import STBTrueType

/// Manages glyph texture atlas for efficient text rendering
public final class GlyphAtlas {
  let texture: GLuint
  let width: Int32
  let height: Int32
  var glyphs: [Int32: Glyph] = [:]

  private init(pixels: [UInt8], width: Int32, height: Int32, glyphs: [Glyph]) {
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

    // Calculate UV coordinates for each glyph
    for glyph in glyphs {
      var updatedGlyph = glyph
      updatedGlyph.u0 = Float(updatedGlyph.atlasX) / Float(width)
      updatedGlyph.u1 = Float(updatedGlyph.atlasX + updatedGlyph.width) / Float(width)
      // Flip V coordinates because glyph bitmaps are top-to-bottom
      // but OpenGL texture coordinates are bottom-left origin
      let vTop = Float(updatedGlyph.atlasY) / Float(height)
      let vBottom = Float(updatedGlyph.atlasY + updatedGlyph.height) / Float(height)
      updatedGlyph.v0 = 1.0 - vBottom
      updatedGlyph.v1 = 1.0 - vTop
      self.glyphs[updatedGlyph.codepoint] = updatedGlyph
    }
  }

  deinit {
    var t = texture
    glDeleteTextures(1, &t)
  }

  /// Build a new glyph atlas for the given text and font
  static func build(for text: String, font: TrueTypeFont, padding: Int32 = 2) -> GlyphAtlas? {
    // Collect unique codepoints from the text using Unicode scalars
    var codepoints: [Int32] = []
    var seen = Set<Int32>()
    for scalar in text.unicodeScalars {
      let codepoint = Int32(scalar.value)
      if seen.insert(codepoint).inserted {
        codepoints.append(codepoint)
      }
    }

    // Load glyph data
    var glyphs: [Glyph] = []
    var rowWidth: Int32 = 0
    var rowHeight: Int32 = 0

    for (i, codepoint) in codepoints.enumerated() {
      guard let glyphBitmap = font.getGlyphBitmap(for: codepoint) else { continue }
      let next = (i + 1 < codepoints.count) ? codepoints[i + 1] : nil
      let advance = font.getAdvance(for: codepoint, next: next)

      glyphs.append(
        Glyph(
          codepoint: codepoint,
          width: glyphBitmap.width,
          height: glyphBitmap.height,
          xOffset: glyphBitmap.xoff,
          yOffset: glyphBitmap.yoff,
          advance: advance,
          atlasX: 0,  // Will be set during packing
          atlasY: 0
        ))

      rowWidth += glyphBitmap.width + padding
      rowHeight = max(rowHeight, glyphBitmap.height)
    }

    guard !glyphs.isEmpty else { return nil }

    // Create atlas texture
    let atlasWidth = max(64, rowWidth)
    let atlasHeight = max(64, rowHeight)
    var pixels = [UInt8](repeating: 0, count: Int(atlasWidth * atlasHeight))

    // Pack glyphs into atlas
    var cursorX: Int32 = 0
    for i in 0..<glyphs.count {
      let codepoint = glyphs[i].codepoint
      guard let glyphBitmap = font.getGlyphBitmap(for: codepoint) else { continue }

      // Copy glyph bitmap to atlas
      for y in 0..<glyphBitmap.height {
        let dstRow = Int(y * atlasWidth + cursorX)
        let srcRow = Int(y * glyphBitmap.width)
        memcpy(
          &pixels[dstRow],
          glyphBitmap.pixels[srcRow...].withUnsafeBufferPointer { $0.baseAddress },
          Int(glyphBitmap.width)
        )
      }

      // Update glyph atlas position
      var g = glyphs[i]
      g.atlasX = cursorX
      g.atlasY = 0
      glyphs[i] = g
      cursorX += glyphBitmap.width + padding
    }

    return GlyphAtlas(pixels: pixels, width: atlasWidth, height: atlasHeight, glyphs: glyphs)
  }
}

/// Represents a single glyph in the atlas
struct Glyph {
  let codepoint: Int32
  let width: Int32
  let height: Int32
  let xOffset: Int32
  let yOffset: Int32
  let advance: Float
  var u0: Float = 0
  var v0: Float = 0
  var u1: Float = 0
  var v1: Float = 0
  var atlasX: Int32 = 0
  var atlasY: Int32 = 0
}
