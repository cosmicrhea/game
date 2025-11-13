/// OpenGL Framebuffer Object for off-screen rendering
public final class GLFramebuffer {
  private var fbo: GLuint = 0
  private var texture: GLuint = 0
  private var rbo: GLuint = 0
  private let size: Size
  private let scale: Float

  public var framebufferSize: Size { size }

  public init(size: Size, scale: Float) {
    self.size = size
    self.scale = scale
    createFramebuffer()
  }

  deinit {
    destroyFramebuffer()
  }

  private func createFramebuffer() {
    // Validate dimensions
    let scaledWidth = Int(size.width * scale)
    let scaledHeight = Int(size.height * scale)

    if scaledWidth <= 0 || scaledHeight <= 0 {
      logger.error("ERROR: Invalid framebuffer dimensions: \(scaledWidth)x\(scaledHeight)")
      return
    }

    // Create framebuffer
    glGenFramebuffers(1, &fbo)
    glBindFramebuffer(GL_FRAMEBUFFER, fbo)

    // Create texture
    glGenTextures(1, &texture)
    GLStats.incrementTextures()
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(
      GL_TEXTURE_2D, 0, GL_RGBA,
      GLsizei(size.width * scale), GLsizei(size.height * scale),
      0, GL_RGBA, GL_UNSIGNED_BYTE, nil
    )
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    // Attach texture to framebuffer
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)

    // Create renderbuffer for depth/stencil
    glGenRenderbuffers(1, &rbo)
    glBindRenderbuffer(GL_RENDERBUFFER, rbo)
    glRenderbufferStorage(
      GL_RENDERBUFFER, GL_DEPTH24_STENCIL8,
      GLsizei(size.width * scale), GLsizei(size.height * scale)
    )
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, rbo)

    // Check framebuffer completeness
    let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
    if status != GL_FRAMEBUFFER_COMPLETE {
      logger.error("Framebuffer not complete: \(status)")
    }

    // Unbind
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
  }

  private func destroyFramebuffer() {
    if fbo != 0 {
      glDeleteFramebuffers(1, &fbo)
      fbo = 0
    }
    if texture != 0 {
      glDeleteTextures(1, &texture)
      GLStats.decrementTextures()
      texture = 0
    }
    if rbo != 0 {
      glDeleteRenderbuffers(1, &rbo)
      rbo = 0
    }
  }

  /// Detach and return the color texture ID, preventing it from being deleted on destroy.
  func detachTexture() -> UInt64 {
    let id = UInt64(texture)
    texture = 0
    return id
  }

  public func bind() {
    glBindFramebuffer(GL_FRAMEBUFFER, fbo)
    glViewport(0, 0, GLsizei(size.width * scale), GLsizei(size.height * scale))
  }

  public func getTextureID() -> UInt64 {
    return UInt64(texture)
  }

  func drawTexture(in rect: Rect, program: GLProgram) {
    // Create quad vertices for the framebuffer texture
    let x = rect.origin.x
    let y = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    let vertices: [Float] = [
      x, y, 0.0, 1.0,  // bottom-left (flipped V)
      x + w, y, 1.0, 1.0,  // bottom-right (flipped V)
      x + w, y + h, 1.0, 0.0,  // top-right (flipped V)
      x, y + h, 0.0, 0.0,  // top-left (flipped V)
    ]

    let indices: [UInt32] = [
      0, 1, 2,  // first triangle
      2, 3, 0,  // second triangle
    ]

    // Create VAO, VBO, EBO
    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0
    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_STATIC_DRAW)

    // Set vertex attributes
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), UnsafeRawPointer(bitPattern: 0))
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride))

    // Bind texture
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texture)
    program.setInt("uTexture", value: 0)

    // Draw
    glDrawElements(GL_TRIANGLES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)

    // Cleanup
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }
}
