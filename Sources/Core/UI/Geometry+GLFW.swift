import struct GLFW.Point
import struct GLFW.Size

extension Point {
  public init(_ glfwPoint: GLFW.Point) {
    self.x = Float(glfwPoint.x)
    self.y = Float(glfwPoint.y)
  }
}

extension Size {
  public init(_ glfwSize: GLFW.Size) {
    self.width = Float(glfwSize.width)
    self.height = Float(glfwSize.height)
  }
}
