public struct Color: Sendable {
  public var red: Float
  public var green: Float
  public var blue: Float
  public var alpha: Float

  public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1.0) {
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  public static let white = Color(1, 1, 1, 1)
  public static let black = Color(0, 0, 0, 1)
  public static let magenta = Color(1, 0, 1, 1)
  public static let clear = Color(0, 0, 0, 0)
}
