@MainActor
public final class ColorWell: OptionsControl {
  public var frame: Rect
  public var isFocused: Bool = false

  public var color: Color

  public var cornerRadius: Float = 6
  public var borderWidth: Float = 2
  public var borderColor: Color = Color.gray500.withAlphaComponent(0.45)
  public var checkerColorA: Color = Color.gray400.withAlphaComponent(0.25)
  public var checkerColorB: Color = Color.gray700.withAlphaComponent(0.25)

  public init(frame: Rect = .zero, color: Color = .white) {
    self.frame = frame
    self.color = color
  }

  public func draw() {
    // Checkerboard background to show alpha
    let cell: Float = 6
    var y: Float = frame.origin.y
    var toggle = false
    while y < frame.maxY {
      var x: Float = frame.origin.x
      toggle = !toggle
      while x < frame.maxX {
        let w = min(cell, frame.maxX - x)
        let h = min(cell, frame.maxY - y)
        Rect(x: x, y: y, width: w, height: h).fill(with: toggle ? checkerColorA : checkerColorB)
        toggle.toggle()
        x += cell
      }
      y += cell
    }

    // Fill with current color
    RoundedRect(frame, cornerRadius: cornerRadius).draw(color: color)
    // Border
    RoundedRect(frame, cornerRadius: cornerRadius)
      .stroke(color: borderColor, lineWidth: borderWidth)
  }

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool { return false }
  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool { return frame.contains(position) }
  public func handleMouseMove(at position: Point) {}
  public func handleMouseUp() {}
}
