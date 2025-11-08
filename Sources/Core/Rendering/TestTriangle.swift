final class TestTriangle {
  private var vertexBuffer: GLuint = 0
  private var vertexArray: GLuint = 0

  init() {
    let vertices: [Float] = [
      -0.5, -0.5, 0.0,
      0.5, -0.5, 0.0,
      0.0, 0.5, 0.0,
    ]

    glGenBuffers(1, &vertexBuffer)
    glGenVertexArrays(1, &vertexArray)

    glBindVertexArray(vertexArray)
    glBindBuffer(GL_ARRAY_BUFFER, vertexArray)
    glBufferData(
      GL_ARRAY_BUFFER,
      vertices.count * MemoryLayout<Float>.stride,
      vertices,
      GL_STATIC_DRAW
    )
    glVertexAttribPointer(
      index: 0,
      size: 3,
      type: GL_FLOAT,
      normalized: false,
      stride: GLsizei(3 * MemoryLayout<Float>.stride),
      pointer: nil
    )
    glEnableVertexAttribArray(0)
  }

  deinit {
    if vertexBuffer != 0 {
      var b = vertexBuffer
      glDeleteBuffers(1, &b)
    }
    if vertexArray != 0 {
      var a = vertexArray
      glDeleteVertexArrays(1, &a)
    }
  }

  func draw() {
    glBindVertexArray(vertexArray)
    glDrawArrays(GL_TRIANGLES, 0, 3)
  }
}
