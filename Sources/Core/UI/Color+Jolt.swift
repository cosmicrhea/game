import typealias Jolt.Color

extension Color {
  public init(_ joltColor: Jolt.Color) {
    // Jolt.Color is UInt32 with RGBA packed as:
    // Bits 0-7: Red, Bits 8-15: Green, Bits 16-23: Blue, Bits 24-31: Alpha
    let redByte = UInt8((joltColor >> 0) & 0xFF)
    let greenByte = UInt8((joltColor >> 8) & 0xFF)
    let blueByte = UInt8((joltColor >> 16) & 0xFF)
    let alphaByte = UInt8((joltColor >> 24) & 0xFF)

    self.red = Float(redByte) / 255.0
    self.green = Float(greenByte) / 255.0
    self.blue = Float(blueByte) / 255.0
    self.alpha = Float(alphaByte) / 255.0
  }

  public var joltColor: Jolt.Color {
    func toByte(_ value: Float) -> UInt8 {
      let scaled = Int((value * 255.0).rounded())
      return UInt8(clamping: scaled)
    }

    let redByte = UInt32(toByte(red))
    let greenByte = UInt32(toByte(green)) << 8
    let blueByte = UInt32(toByte(blue)) << 16
    let alphaByte = UInt32(toByte(alpha)) << 24

    return redByte | greenByte | blueByte | alphaByte
  }
}
