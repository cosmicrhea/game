import struct GLFW.Color

extension Color {
  public init(_ glfwColor: GLFW.Color) {
    self.red = Float(glfwColor.redBits) / 255.0
    self.green = Float(glfwColor.greenBits) / 255.0
    self.blue = Float(glfwColor.blueBits) / 255.0
    self.alpha = Float(glfwColor.alphaBits) / 255.0
  }

  public var glfwColor: GLFW.Color {
    func toByte(_ value: Float) -> UInt8 {
      let scaled = Int((value * 255.0).rounded())
      return UInt8(clamping: scaled)
    }

    return GLFW.Color(
      rBits: toByte(red),
      g: toByte(green),
      b: toByte(blue),
      a: toByte(alpha)
    )
  }
}
