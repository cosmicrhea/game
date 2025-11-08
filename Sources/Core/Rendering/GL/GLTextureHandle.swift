final class GLTextureHandle: @unchecked Sendable {
  let id: GLuint

  init(id: GLuint) {
    self.id = id
    GLStats.incrementTextures()
  }

  deinit {
    var t = id
    glDeleteTextures(1, &t)
    GLStats.decrementTextures()
  }
}
