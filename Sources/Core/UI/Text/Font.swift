import STBTrueType

/// The representation of a font in the game.
public final class Font {
  // MARK: - Cache

  private struct CacheKey: Hashable {
    let fontPath: String
    let pixelHeight: Int
  }

  private struct CachedFont {
    let trueTypeFont: TrueTypeFont
    let baselinePx: Float
    let maxAboveBaseline: Float
    let maxBelowBaseline: Float
  }

  private nonisolated(unsafe) static var cache: [CacheKey: CachedFont] = [:]
  private static let cacheLock = NSLock()

  private let trueTypeFont: TrueTypeFont
  private let maxAboveBaseline: Float
  private let maxBelowBaseline: Float
  private let baselinePx: Float
  private let monospacedDigitsEnabled: Bool
  private let digitAdvancePx: Float?

  // MARK: - Font Discovery

  /// Information about a resolved font file.
  public struct ResolvedFont: Sendable {
    /// The URL of the font file.
    public let url: URL
    /// The display name of the font.
    public let displayName: String
    /// The base name of the font (kept for compatibility; equals displayName).
    public let baseName: String
    /// The pixel size of the font, if specified in the filename. Always nil now.
    public let pixelSize: Int?
  }

  private static let defaultFontsPath = "Fonts"

  /// The available fonts in the game, scanned once.
  public static let availableFonts: [ResolvedFont] = {
    let extensions = ["ttf", "otf"]
    var entries: [ResolvedFont] = []
    for ext in extensions {
      let urls = Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: defaultFontsPath) ?? []
      for url in urls {
        let name = url.deletingPathExtension().lastPathComponent
        entries.append(ResolvedFont(url: url, displayName: name, baseName: name, pixelSize: nil))
      }
    }
    return entries.sorted { $0.displayName > $1.displayName }
  }()

  /// Resolves a font by name from the available fonts.
  /// - Parameter name: The name of the font to resolve.
  /// - Returns: The resolved font information, or `nil` if not found.
  public static func resolve(name: String) -> ResolvedFont? {
    // Exact match first
    if let exact = availableFonts.first(where: { $0.displayName == name }) { return exact }
    // Case-insensitive fallback
    if let ci = availableFonts.first(where: { $0.displayName.lowercased() == name.lowercased() }) { return ci }
    return nil
  }

  // Removed legacy name parsing; filenames are used as-is.

  // MARK: - Font Loading

  /// Optional typographic features for layout-time control (no GSUB shaping).
  public struct Features: Sendable, Hashable {
    public let monospaceDigits: Bool
    public init(monospaceDigits: Bool = false) {
      self.monospaceDigits = monospaceDigits
    }
    public static let none = Features()
  }

  /// Creates and returns a font object for the specified font name and pixel size.
  /// - Parameters:
  ///   - fontName: The name of the font to load.
  ///   - pixelHeight: The pixel height of the font; defaults to the font's specified size or 16.
  ///   - features: Optional layout features to control rendering behavior.
  /// - Returns: A new font instance, or `nil` if the font could not be loaded.
  public init?(fontName: String, pixelHeight: Float? = nil, features: Features = .none) {
    guard let entry = Font.resolve(name: fontName) else { return nil }
    let resolvedPixelHeight = pixelHeight ?? 16

    let key = CacheKey(fontPath: entry.url.path, pixelHeight: Int(resolvedPixelHeight.rounded()))

    // Fast path: cached
    Font.cacheLock.lock()
    if let cached = Font.cache[key] {
      Font.cacheLock.unlock()
      self.trueTypeFont = cached.trueTypeFont
      self.baselinePx = cached.baselinePx
      self.maxAboveBaseline = cached.maxAboveBaseline
      self.maxBelowBaseline = cached.maxBelowBaseline
      self.monospacedDigitsEnabled = features.monospaceDigits
      if features.monospaceDigits {
        var maxDigitAdvance: Float = 0
        for cp in 48...57 {  // '0'...'9'
          maxDigitAdvance = max(maxDigitAdvance, cached.trueTypeFont.getAdvance(for: Int32(cp), next: nil))
        }
        self.digitAdvancePx = maxDigitAdvance
      } else {
        self.digitAdvancePx = nil
      }
      return
    }
    Font.cacheLock.unlock()

    // Load and compute, then cache
    guard let ttf = TrueTypeFont(path: entry.url.path, pixelHeight: resolvedPixelHeight) else {
      return nil
    }

    let baseline = ttf.getBaseline()

    // Precompute conservative line metrics by scanning ASCII range
    var above: Float = 0
    var below: Float = 0

    for codepoint in 32...126 {
      if let glyphBitmap = ttf.getGlyphBitmap(for: Int32(codepoint)) {
        let glyphAbove = max(0, -Float(glyphBitmap.yoff))
        let glyphBelow = max(0, Float(glyphBitmap.yoff + glyphBitmap.height))
        above = max(above, glyphAbove)
        below = max(below, glyphBelow)
      }
    }

    let cached = CachedFont(trueTypeFont: ttf, baselinePx: baseline, maxAboveBaseline: above, maxBelowBaseline: below)

    Font.cacheLock.lock()
    Font.cache[key] = cached
    Font.cacheLock.unlock()

    self.trueTypeFont = ttf
    self.baselinePx = baseline
    self.maxAboveBaseline = above
    self.maxBelowBaseline = below
    self.monospacedDigitsEnabled = features.monospaceDigits
    if features.monospaceDigits {
      var maxDigitAdvance: Float = 0
      for cp in 48...57 {
        maxDigitAdvance = max(maxDigitAdvance, ttf.getAdvance(for: Int32(cp), next: nil))
      }
      self.digitAdvancePx = maxDigitAdvance
    } else {
      self.digitAdvancePx = nil
    }
  }

  // MARK: - Font Metrics

  /// Pixel height to move the pen between lines
  public var lineHeight: Float {
    baselineFromTop + maxBelowBaseline
  }

  /// Baseline offset from the top of the line box
  public var baselineFromTop: Float {
    baselinePx
  }

  /// Distance below the baseline to the deepest descender
  public var descentFromBaseline: Float {
    maxBelowBaseline
  }

  // MARK: - Font Operations

  /// Gets the underlying TrueType font for advanced operations.
  /// - Returns: The underlying TrueType font instance.
  public func getTrueTypeFont() -> TrueTypeFont {
    return trueTypeFont
  }

  /// Whether monospaced digits are enabled for this font instance.
  public var monospaceDigits: Bool { monospacedDigitsEnabled }

  /// If monospaced digits are enabled, the fixed advance used for '0'..'9'.
  public var digitCellAdvance: Float? { digitAdvancePx }

  /// Measures the width of a string in points.
  /// - Parameters:
  ///   - text: The text to measure.
  ///   - scale: The scale factor to apply to the measurement.
  /// - Returns: The width of the text in points.
  public func measureWidth(_ text: String, scale: Float = 1.0) -> Float {
    var width: Float = 0
    let scalars = Array(text.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let codepoint = Int32(scalars[i].value)
      let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil

      // Use Font-level advance so features (e.g., monospaced digits) apply
      width += getAdvance(for: codepoint, next: next, scale: scale)
      i += 1
    }

    return width
  }

  /// Gets the advance width for a codepoint, considering the next character for kerning.
  /// - Parameters:
  ///   - codepoint: The Unicode codepoint to get the advance for.
  ///   - next: The next codepoint for kerning calculations, or `nil` if none.
  ///   - scale: The scale factor to apply to the advance.
  /// - Returns: The advance width in points.
  public func getAdvance(for codepoint: Int32, next: Int32?, scale: Float = 1.0) -> Float {
    if monospacedDigitsEnabled, codepoint >= 48, codepoint <= 57, let digitAdvancePx {
      return digitAdvancePx * scale
    }
    return trueTypeFont.getAdvance(for: codepoint, next: next) * scale
  }
}
