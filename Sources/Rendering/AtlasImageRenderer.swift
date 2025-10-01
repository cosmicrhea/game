import Foundation
import GL
import GLFW

/// Renders named sprites from a TexturePacker-style XML atlas next to a PNG.
/// Usage:
///   let atlas = AtlasImageRenderer("UI/InputPrompts/playstation.xml")
///   atlas.draw(name: "playstation_button_circle", x: 100, y: 100, windowSize: (w, h))
final class AtlasImageRenderer {
  private let program: GLProgram
  private var texture: GLuint = 0
  private var atlasWidth: Int32 = 0
  private var atlasHeight: Int32 = 0

  /// Name -> rect in pixel coordinates within the atlas (top-left origin)
  private var nameToRect: [String: (x: Int32, y: Int32, w: Int32, h: Int32)] = [:]

  /// Optional global scale applied at draw time
  var scale: Float = 1.0

  init(_ atlasXMLPath: String) {
    self.program = try! GLProgram("UI/text", "UI/image")

    // Locate XML inside SPM bundle
    guard let baseURL = Bundle.module.resourceURL else { return }
    let xmlURL = baseURL.appendingPathComponent(atlasXMLPath)

    // Parse XML for subtexture rects and imagePath
    let delegate = AtlasXMLParserDelegate()
    if let data = try? Data(contentsOf: xmlURL) {
      let parser = XMLParser(data: data)
      parser.delegate = delegate
      _ = parser.parse()
    }

    // Resolve the PNG path relative to the XML file's directory
    let imageFileName = delegate.imagePath ?? ""
    let imageURL = xmlURL.deletingLastPathComponent().appendingPathComponent(imageFileName)

    // Load image via GLFW.Image extension
    let relativeFromBundle = imageURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
    let img = GLFW.Image(relativeFromBundle)
    atlasWidth = Int32(img.width)
    atlasHeight = Int32(img.height)

    // Upload texture to GL
    var tex: GLuint = 0
    glGenTextures(1, &tex)
    glBindTexture(GL_TEXTURE_2D, tex)

    var bytes: [UInt8] = []
    bytes.reserveCapacity(Int(img.width * img.height * 4))
    img.pixels.forEach { p in
      bytes.append(p.redBits)
      bytes.append(p.greenBits)
      bytes.append(p.blueBits)
      bytes.append(p.alphaBits)
    }

    bytes.withUnsafeBytes { raw in
      glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        GLsizei(img.width),
        GLsizei(img.height),
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        raw.baseAddress
      )
    }

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    self.texture = tex
    self.nameToRect = delegate.nameToRect
  }

  deinit {
    if texture != 0 {
      var t = texture
      glDeleteTextures(1, &t)
    }
  }

  /// Return the unscaled pixel size for a named sprite in the atlas.
  func spriteSize(name: String) -> (w: Int32, h: Int32)? {
    guard let r = nameToRect[name] else { return nil }
    return (r.w, r.h)
  }

  /// Return the scaled size (after applying `scale`).
  func scaledSpriteSize(name: String) -> (w: Float, h: Float)? {
    guard let r = nameToRect[name] else { return nil }
    return (Float(r.w) * scale, Float(r.h) * scale)
  }

  /// Draw the named subtexture with its native size at top-left anchored at (x, y).
  func draw(
    name: String,
    x: Float,
    y: Float,
    windowSize: (w: Int32, h: Int32),
    tint: (Float, Float, Float, Float) = (1, 1, 1, 1),
    opacity: Float = 1.0
  ) {
    guard let rect = nameToRect[name], texture != 0, atlasWidth > 0, atlasHeight > 0 else { return }

    let wPx = Float(rect.w) * scale
    let hPx = Float(rect.h) * scale

    // UVs in top-left origin (shader flips V)
    let u0 = Float(rect.x) / Float(atlasWidth)
    let v0 = Float(rect.y) / Float(atlasHeight)
    let u1 = Float(rect.x + rect.w) / Float(atlasWidth)
    let v1 = Float(rect.y + rect.h) / Float(atlasHeight)

    let verts: [Float] = [
      // x,     y,     u,  v
      x, y, u0, v0,
      x + wPx, y, u1, v0,
      x + wPx, y + hPx, u1, v1,
      x, y + hPx, u0, v1,
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

    // Screen-space ortho matrix (pixel coords -> NDC)
    let W = Float(windowSize.w)
    let H = Float(windowSize.h)
    let mvp: [Float] = [
      2 / W, 0, 0, 0,
      0, 2 / H, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]

    // UI state: blend, no depth/cull
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    program.use()
    mvp.withUnsafeBufferPointer { buf in
      program.setMat4("uMVP", value: buf.baseAddress!)
    }
    program.setVec4("uTint", value: (tint.0, tint.1, tint.2, tint.3 * opacity))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texture)
    program.setInt("uTexture", value: 0)

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

  /// Draw the named subtexture scaled to a target size in pixels at (x, y).
  /// Aspect ratio should be preserved by the caller when computing targetSize.
  func drawScaled(
    name: String,
    x: Float,
    y: Float,
    windowSize: (w: Int32, h: Int32),
    targetSize: (w: Float, h: Float),
    tint: (Float, Float, Float, Float) = (1, 1, 1, 1),
    opacity: Float = 1.0
  ) {
    guard let rect = nameToRect[name], texture != 0, atlasWidth > 0, atlasHeight > 0 else { return }

    let wPx = targetSize.w
    let hPx = targetSize.h

    let u0 = Float(rect.x) / Float(atlasWidth)
    let v0 = Float(rect.y) / Float(atlasHeight)
    let u1 = Float(rect.x + rect.w) / Float(atlasWidth)
    let v1 = Float(rect.y + rect.h) / Float(atlasHeight)

    let verts: [Float] = [
      x, y, u0, v0,
      x + wPx, y, u1, v0,
      x + wPx, y + hPx, u1, v1,
      x, y + hPx, u0, v1,
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

    let W = Float(windowSize.w)
    let H = Float(windowSize.h)
    let mvp: [Float] = [
      2 / W, 0, 0, 0,
      0, 2 / H, 0, 0,
      0, 0, -1, 0,
      -1, -1, 0, 1,
    ]

    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    program.use()
    mvp.withUnsafeBufferPointer { buf in
      program.setMat4("uMVP", value: buf.baseAddress!)
    }
    program.setVec4("uTint", value: (tint.0, tint.1, tint.2, tint.3 * opacity))

    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texture)
    program.setInt("uTexture", value: 0)

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
}

final class AtlasXMLParserDelegate: NSObject, XMLParserDelegate {
  var imagePath: String? = nil
  var nameToRect: [String: (x: Int32, y: Int32, w: Int32, h: Int32)] = [:]

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    if elementName == "TextureAtlas" {
      imagePath = attributeDict["imagePath"]
    } else if elementName == "SubTexture" {
      guard let name = attributeDict["name"],
        let x = attributeDict["x"],
        let y = attributeDict["y"],
        let w = attributeDict["width"],
        let h = attributeDict["height"],
        let xi = Int32(x), let yi = Int32(y), let wi = Int32(w), let hi = Int32(h)
      else { return }
      nameToRect[name] = (x: xi, y: yi, w: wi, h: hi)
    }
  }
}
