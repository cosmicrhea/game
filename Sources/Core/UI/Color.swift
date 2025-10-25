/// A color value with red, green, blue, and alpha components.
public struct Color: Sendable, Equatable {
  /// The red component (0.0 to 1.0).
  public var red: Float
  /// The green component (0.0 to 1.0).
  public var green: Float
  /// The blue component (0.0 to 1.0).
  public var blue: Float
  /// The alpha component (0.0 to 1.0).
  public var alpha: Float

  /// Creates a new color with the specified components.
  /// - Parameters:
  ///   - red: The red component (0.0 to 1.0).
  ///   - green: The green component (0.0 to 1.0).
  ///   - blue: The blue component (0.0 to 1.0).
  ///   - alpha: The alpha component (0.0 to 1.0); defaults to 1.0.
  public init(red: Float, green: Float, blue: Float, alpha: Float = 1.0) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Creates a new color with the specified components using positional parameters.
  /// - Parameters:
  ///   - red: The red component (0.0 to 1.0).
  ///   - green: The green component (0.0 to 1.0).
  ///   - blue: The blue component (0.0 to 1.0).
  ///   - alpha: The alpha component (0.0 to 1.0); defaults to 1.0.
  public init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1.0) {
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  /// Creates a color object that has the same color space and component values as the receiver, but has the specified alpha component.
  /// - Parameter alpha: The opacity value of the new color object, specified as a value from 0.0 to 1.0. Alpha values below 0.0 are interpreted as 0.0, and values above 1.0 are interpreted as 1.0.
  /// - Returns: The new Color object.
  public func withAlphaComponent(_ alpha: Float) -> Color {
    let clampedAlpha = max(0.0, min(1.0, alpha))
    return Color(red: red, green: green, blue: blue, alpha: clampedAlpha)
  }
}


// MARK: - Accent Color (dynamic, app-wide)

// File-scoped storage for the dynamic accent color. Defaults to rose.
nonisolated(unsafe) private var _globalAccentColor: Color = .rose900

extension Color {
  /// Global UI accent color used by controls like Switch and Slider fills.
  /// This can be changed at runtime to theme the UI.
  @MainActor public static var accent: Color {
    get { _globalAccentColor }
    set {
      _globalAccentColor = newValue
      // Persist to config as RGBA string
      let r = String(format: "%.4f", newValue.red)
      let g = String(format: "%.4f", newValue.green)
      let b = String(format: "%.4f", newValue.blue)
      let a = String(format: "%.4f", newValue.alpha)
      Config.current.accentRGBA = "\(r),\(g),\(b),\(a)"
    }
  }
}

// MARK: - Built-in Color Palette

extension Color {
  public static let white = Color(1, 1, 1, 1)
  public static let black = Color(0, 0, 0, 1)
  public static let red = Color(1, 0, 0, 1)
  public static let green = Color(0, 1, 0, 1)
  public static let blue = Color(0, 0, 1, 1)
  public static let yellow = Color(1, 1, 0, 1)
  public static let cyan = Color(0, 1, 1, 1)
  public static let magenta = Color(1, 0, 1, 1)
  public static let clear = Color(0, 0, 0, 0)

  public static let indigo = Color(0.3098, 0.2745, 0.8980, 1)
  public static let amber = Color(0.9608, 0.6196, 0.0431, 1)
  public static let amber800 = Color(0.6, 0.4, 0.05, 1)
  public static let teal = Color(0.0784, 0.7216, 0.6510, 1)
  public static let orange = Color(0.9765, 0.4510, 0.0863, 1)
  public static let purple = Color(0.6588, 0.3333, 0.9686, 1)
  public static let emerald = Color(0.0627, 0.7255, 0.5059, 1)
  public static let rose = Color(0.9569, 0.2471, 0.3686, 1)
  public static let rose700 = Color(0.7569, 0.1471, 0.2686, 1)
  public static let rose800 = Color(0.5569, 0.0471, 0.1686, 1)
  public static let rose900 = Color(0.3569, 0.0471, 0.0686, 1)

  public static let gray100 = Color(0.9529, 0.9569, 0.9647, 1)
  public static let gray200 = Color(0.8059, 0.8333, 0.8804, 1)
  public static let gray300 = Color(0.7059, 0.7333, 0.7804, 1)
  public static let gray400 = Color(0.6059, 0.6333, 0.6804, 1)
  public static let gray500 = Color(0.4196, 0.4471, 0.5020, 1)
  public static let gray700 = Color(0.2706, 0.2902, 0.3294, 1)
  public static let gray900 = Color(0.0667, 0.0667, 0.0667, 1)

  // Blueprint colors
  public static let blueprintBackground = Color(0.05, 0.08, 0.15, 1)  // Dark blue
  public static let blueprintGrid = Color(0.7, 0.8, 0.9, 1)  // Light blue

  // Slot colors
  public static let slotBackground = Color(0.2, 0.2, 0.2, 1)
  public static let slotBorder = Color(0.5, 0.6, 0.6, 1)
  public static let slotBorderHighlight = Color(0.7, 0.7, 0.7, 1)
  public static let slotBorderShadow = Color(0.2, 0.2, 0.2, 1)
  public static let slotActive = Color(0.47, 0.47, 0.47, 1)
  public static let slotSelected = Color(0.32, 0.32, 0.32, 1)
  public static let slotHovered = Color(0.22, 0.22, 0.22, 1)
}
