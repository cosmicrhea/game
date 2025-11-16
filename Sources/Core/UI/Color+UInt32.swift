extension Color {
  /// Creates a color from a UInt32 RGBA value (web hex format: #RRGGBBAA).
  /// - Parameter rgba: The RGBA color value packed as:
  ///   Bits 24-31: Red, Bits 16-23: Green, Bits 8-15: Blue, Bits 0-7: Alpha
  public init(_ rgba: UInt32) {
    let redByte = UInt8((rgba >> 24) & 0xFF)
    let greenByte = UInt8((rgba >> 16) & 0xFF)
    let blueByte = UInt8((rgba >> 8) & 0xFF)
    let alphaByte = UInt8((rgba >> 0) & 0xFF)

    self.red = Float(redByte) / 255.0
    self.green = Float(greenByte) / 255.0
    self.blue = Float(blueByte) / 255.0
    self.alpha = Float(alphaByte) / 255.0
  }

  /// Returns the color as a UInt32 RGBA value (web hex format: #RRGGBBAA).
  /// Bits 24-31: Red, Bits 16-23: Green, Bits 8-15: Blue, Bits 0-7: Alpha
  public var rgba: UInt32 {
    func toByte(_ value: Float) -> UInt8 {
      let scaled = Int((value * 255.0).rounded())
      return UInt8(clamping: scaled)
    }

    let redByte = UInt32(toByte(red)) << 24
    let greenByte = UInt32(toByte(green)) << 16
    let blueByte = UInt32(toByte(blue)) << 8
    let alphaByte = UInt32(toByte(alpha)) << 0

    return redByte | greenByte | blueByte | alphaByte
  }

  /// Creates a color from a UInt32 ABGR value (Jolt format).
  /// - Parameter abgr: The ABGR color value packed as:
  ///   Bits 0-7: Red, Bits 8-15: Green, Bits 16-23: Blue, Bits 24-31: Alpha
  public init(abgr: UInt32) {
    let redByte = UInt8((abgr >> 0) & 0xFF)
    let greenByte = UInt8((abgr >> 8) & 0xFF)
    let blueByte = UInt8((abgr >> 16) & 0xFF)
    let alphaByte = UInt8((abgr >> 24) & 0xFF)

    self.red = Float(redByte) / 255.0
    self.green = Float(greenByte) / 255.0
    self.blue = Float(blueByte) / 255.0
    self.alpha = Float(alphaByte) / 255.0
  }

  /// Returns the color as a UInt32 ABGR value (Jolt format).
  /// Bits 0-7: Red, Bits 8-15: Green, Bits 16-23: Blue, Bits 24-31: Alpha
  public var abgr: UInt32 {
    func toByte(_ value: Float) -> UInt8 {
      let scaled = Int((value * 255.0).rounded())
      return UInt8(clamping: scaled)
    }

    let redByte = UInt32(toByte(red)) << 0
    let greenByte = UInt32(toByte(green)) << 8
    let blueByte = UInt32(toByte(blue)) << 16
    let alphaByte = UInt32(toByte(alpha)) << 24

    return redByte | greenByte | blueByte | alphaByte
  }
}
