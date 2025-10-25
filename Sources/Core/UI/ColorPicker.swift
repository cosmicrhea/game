@MainActor
public final class ColorPicker: OptionsControl {
  // MARK: - Public API

  public var frame: Rect
  public var isFocused: Bool = false

  /// Currently selected color (RGB in 0-1, alpha preserved on changes)
  public var color: Color {
    didSet {
      onColorChanged?(color)
    }
  }

  /// Called whenever `color` changes.
  public var onColorChanged: ((Color) -> Void)?

  /// Optional: value/brightness component when selecting hue/saturation on wheel.
  /// Defaults to 1.0 (full brightness). Updating this will regenerate the selector position.
  public var valueComponent: Float = 1.0 { didSet { valueComponent = max(0, min(1, valueComponent)) } }

  /// Insets inside `frame` used for the wheel placement.
  public var contentInset: Float = 4

  /// Size of the selection handle in points
  public var knobSize: Float = 12

  /// Colors for the selection handle
  public var knobFill: Color = .clear
  public var knobStrokeInner: Color = Color.white
  public var knobStrokeOuter: Color = Color.black.withAlphaComponent(0.75)

  // MARK: - Private

  private var isDragging: Bool = false
  private var wheelImage: Image? = nil
  private var wheelPixelSize: Int = 0

  public init(frame: Rect = .zero, color: Color = .white) {
    self.frame = frame
    self.color = color
    // Initialize value component from current color
    let (_, _, v) = Self.rgbToHsv(color.red, color.green, color.blue)
    self.valueComponent = v
  }

  // MARK: - Drawing

  public func draw() {
    // Subtle background behind the wheel for contrast
    let bgRect = frame
    RoundedRect(bgRect, cornerRadius: 6).draw(color: Color.gray700.withAlphaComponent(0.20))

    // Compute square area for the wheel centered within frame
    let size = min(frame.size.width, frame.size.height) - contentInset * 2
    if size <= 2 { return }
    let wheelRect = Rect(
      x: frame.midX - size * 0.5,
      y: frame.midY - size * 0.5,
      width: size,
      height: size
    )

    // Ensure wheel image exists at appropriate resolution
    let pixelSize = max(8, Int(size.rounded()))
    ensureWheelImage(diameterPx: pixelSize)

    if let image = wheelImage {
      image.draw(in: wheelRect)
    }

    // Draw selection knob at hue/sat position
    let (h, s, _) = Self.rgbToHsv(color.red, color.green, color.blue)
    let radius = size * 0.5
    let angle = h * 2 * .pi
    let r = s * radius
    let cx = wheelRect.midX + cosf(angle) * r
    let cy = wheelRect.midY + sinf(angle) * r

    let k = knobSize
    let knobRect = Rect(x: cx - k * 0.5, y: cy - k * 0.5, width: k, height: k)
    RoundedRect(knobRect, cornerRadius: k * 0.5).draw(color: knobFill)
    RoundedRect(knobRect, cornerRadius: k * 0.5).stroke(color: knobStrokeInner, lineWidth: 2)
    RoundedRect(knobRect.insetBy(dx: -1, dy: -1), cornerRadius: (k + 2) * 0.5)
      .stroke(color: knobStrokeOuter, lineWidth: 1)
  }

  // MARK: - Input

  @discardableResult
  public func handleKey(_ key: Keyboard.Key) -> Bool { return false }

  @discardableResult
  public func handleMouseDown(at position: Point) -> Bool {
    guard let wheelRect = wheelRect() else { return false }
    guard wheelRect.contains(position) else { return false }
    isDragging = true
    updateColor(from: position, wheelRect: wheelRect)
    return true
  }

  public func handleMouseMove(at position: Point) {
    guard isDragging, let wheelRect = wheelRect() else { return }
    updateColor(from: position, wheelRect: wheelRect)
  }

  public func handleMouseUp() { isDragging = false }

  // MARK: - Helpers

  private func wheelRect() -> Rect? {
    let size = min(frame.size.width, frame.size.height) - contentInset * 2
    if size <= 2 { return nil }
    return Rect(
      x: frame.midX - size * 0.5,
      y: frame.midY - size * 0.5,
      width: size,
      height: size
    )
  }

  private func updateColor(from position: Point, wheelRect: Rect) {
    let center = Point(wheelRect.midX, wheelRect.midY)
    let dx = position.x - center.x
    let dy = position.y - center.y
    let angle = atan2f(dy, dx)
    let dist = sqrtf(dx * dx + dy * dy)
    let radius = min(wheelRect.size.width, wheelRect.size.height) * 0.5
    let s = max(0, min(1, dist / max(1e-6, radius)))
    var h = angle / (2 * .pi)
    if h < 0 { h += 1 }

    let (r, g, b) = Self.hsvToRgb(h, s, valueComponent)
    color = Color(r, g, b, color.alpha)
  }

  private func ensureWheelImage(diameterPx: Int) {
    if wheelImage != nil && wheelPixelSize == diameterPx { return }
    wheelPixelSize = diameterPx

    let w = diameterPx
    let h = diameterPx
    let radius = Float(diameterPx) * 0.5
    let cx = radius
    let cy = radius

    var pixels = [UInt8](repeating: 0, count: w * h * 4)

    for y in 0..<h {
      let fy = Float(y)
      for x in 0..<w {
        let fx = Float(x)
        let dx = fx - cx + 0.5
        let dy = fy - cy + 0.5
        let dist = sqrtf(dx * dx + dy * dy)
        let rNorm = dist / max(1e-6, radius)
        let inside = rNorm <= 1.0
        let idx = (y * w + x) * 4
        if inside {
          var hue = atan2f(dy, dx) / (2 * .pi)
          if hue < 0 { hue += 1 }
          let sat = max(0, min(1, rNorm))
          let (rr, gg, bb) = Self.hsvToRgb(hue, sat, 1.0)
          pixels[idx + 0] = UInt8(max(0, min(255, Int(rr * 255))))
          pixels[idx + 1] = UInt8(max(0, min(255, Int(gg * 255))))
          pixels[idx + 2] = UInt8(max(0, min(255, Int(bb * 255))))
          pixels[idx + 3] = 255
        } else {
          pixels[idx + 0] = 0
          pixels[idx + 1] = 0
          pixels[idx + 2] = 0
          pixels[idx + 3] = 0
        }
      }
    }

    wheelImage = Image.uploadToGL(pixels: pixels, width: w, height: h, pixelScale: 1.0)
  }

  // MARK: - Color Math (HSV <-> RGB)

  private static func hsvToRgb(_ h: Float, _ s: Float, _ v: Float) -> (Float, Float, Float) {
    let hh = (h - floor(h)) * 6.0
    let i = Int(floor(hh))
    let f = hh - Float(i)
    let p = v * (1.0 - s)
    let q = v * (1.0 - s * f)
    let t = v * (1.0 - s * (1.0 - f))
    switch i % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
  }

  private static func rgbToHsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
    let maxC = max(r, max(g, b))
    let minC = min(r, min(g, b))
    let delta = maxC - minC
    var h: Float = 0
    let s: Float = maxC == 0 ? 0 : (delta / maxC)
    let v: Float = maxC

    if delta != 0 {
      if maxC == r {
        h = (g - b) / delta
        if g < b { h += 6 }
      } else if maxC == g {
        h = (b - r) / delta + 2
      } else {
        h = (r - g) / delta + 4
      }
      h /= 6
    }
    return (h, s, v)
  }
}
