import Foundation
import GL
import GLFW

/// Draws a single image file as a textured quad in screen space.
/// Usage:
///   let img = ImageRenderer("common/divider-fade-000.png")
///   img.draw(x: 100, y: 100, windowSize: (Int32(WIDTH), Int32(HEIGHT)))
final class ImageRenderer {
  private let program: GLProgram
  private var texture: GLuint = 0
  private var width: Int32 = 0
  private var height: Int32 = 0

  /// Optional global scale applied at draw time
  var scale: Float = 1.0

  init(_ assetPath: String) {
    // Reuse UI vertex shader and a minimal fragment shader
    self.program = try! GLProgram("UI/text", "UI/image")

    // Load pixels via GLFW.Image extension (uses ImageFormats under the hood)
    let img = GLFW.Image(assetPath)
    self.width = Int32(img.width)
    self.height = Int32(img.height)

    var tex: GLuint = 0
    glGenTextures(1, &tex)
    glBindTexture(GL_TEXTURE_2D, tex)

    // Upload RGBA8 texture
    // Convert GLFW.Color array to a contiguous [UInt8]
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
  }

  deinit {
    if texture != 0 {
      var t = texture
      glDeleteTextures(1, &t)
    }
  }

  /// Draw the image with its native size at top-left anchored at (x, y) in pixels.
  func draw(
    x: Float, y: Float, windowSize: (w: Int32, h: Int32),
    tint: (Float, Float, Float, Float) = (1, 1, 1, 1),
    opacity: Float = 1.0
  ) {
    guard texture != 0 else { return }

    // Build a quad in pixel space with UVs
    let w = Float(width) * scale
    let h = Float(height) * scale
    let verts: [Float] = [
      // x,   y,    u, v
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

    // Ensure filled polys regardless of app's polygon mode
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
}
