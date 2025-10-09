import Foundation
import GL
import GLMath

/// Simple debug drawing utility for drawing rectangles and other debug shapes
public final class DebugDrawer {
  private let program: GLProgram

  public init() {
    self.program = try! GLProgram("Common/debug")
  }

  /// Draw a debug rectangle outline in magenta
  public func drawRect(
    x: Float, y: Float, width: Float, height: Float,
    windowSize: (w: Int32, h: Int32),
    lineWidth: Float = 2.0
  ) {
    // Draw rectangle as 4 line segments
    let vertices: [Float] = [
      // x, y, r, g, b, a
      x, y, 1, 0.3, 0.8, 1,  // top-left
      x + width, y, 1, 0.3, 0.8, 1,  // top-right
      x + width, y + height, 1, 0.3, 0.8, 1,  // bottom-right
      x, y + height, 1, 0.3, 0.8, 1,  // bottom-left
    ]
    let indices: [UInt32] = [0, 1, 1, 2, 2, 3, 3, 0]  // 4 line segments

    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0

    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(
      GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_DYNAMIC_DRAW
    )
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices,
      GL_DYNAMIC_DRAW
    )

    // Position attribute
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 2, GL_FLOAT, false, GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 0)
    )

    // Color attribute
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 4, GL_FLOAT, false, GLsizei(6 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
    )

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
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == true
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == false
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    program.use()
    mvp.withUnsafeBufferPointer { buf in
      program.setMat4("uMVP", value: buf.baseAddress!)
    }

    // Set line width
    glLineWidth(lineWidth)

    glBindVertexArray(vao)
    glDrawElements(GL_LINES, GLsizei(indices.count), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore state
    glLineWidth(1.0)
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }

    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
    glDeleteVertexArrays(1, &vao)
  }
}

/// Global debug drawing instance
nonisolated(unsafe) public let Debug = DebugDrawer()
