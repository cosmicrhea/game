import Foundation
import STBTrueType

/// Unified font handling that combines font discovery and loading
public final class Font {
  private let trueTypeFont: TrueTypeFont
  private let maxAboveBaseline: Float
  private let maxBelowBaseline: Float
  private let baselinePx: Float

  // MARK: - Font Discovery

  public struct ResolvedFont {
    public let url: URL
    public let displayName: String
    public let baseName: String
    public let pixelSize: Int?
  }

  private static let defaultFontsPath = "Fonts"

  public static var availableFonts: [ResolvedFont] {
    let extensions = ["ttf", "otf"]
    var entries: [ResolvedFont] = []

    for ext in extensions {
      let urls = Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: defaultFontsPath) ?? []

      for url in urls {
        let name = url.deletingPathExtension().lastPathComponent
        let (base, size) = parseBaseAndSize(from: name)
        entries.append(ResolvedFont(url: url, displayName: name, baseName: base, pixelSize: size))
      }
    }

    return entries.sorted { $0.displayName > $1.displayName }
  }

  public static func resolve(name: String) -> ResolvedFont? {
    let (requestedBase, requestedSize) = parseBaseAndSize(from: name)
    let matches = availableFonts.filter { $0.displayName == name || $0.baseName == requestedBase }
    if matches.isEmpty { return nil }

    if let size = requestedSize {
      let sized = matches.first(where: { $0.pixelSize == size })
      if let sized = sized { return sized }
    }

    // Prefer TTF if both TTF/OTF exist for the same base name
    if let preferred = matches.first(where: { $0.url.pathExtension.lowercased() == "ttf" }) {
      return preferred
    }
    return matches.first
  }

  private static func parseBaseAndSize(from displayName: String) -> (String, Int?) {
    // Matches: Name (13px)
    guard let open = displayName.lastIndex(of: "("),
      let close = displayName.lastIndex(of: ")"),
      open < close
    else {
      return (displayName, nil)
    }

    let sizePart = displayName[displayName.index(after: open)..<close]
    if sizePart.hasSuffix("px"), let num = Int(sizePart.dropLast(2)) {
      let base = displayName[..<displayName.index(before: open)].trimmingCharacters(in: .whitespaces)
      return (String(base), num)
    }
    return (displayName, nil)
  }

  // MARK: - Font Loading

  public init?(fontName: String, pixelHeight: Float? = nil) {
    guard let entry = Font.resolve(name: fontName) else { return nil }
    let resolvedPixelHeight = pixelHeight ?? entry.pixelSize.map(Float.init) ?? 16

    guard let trueTypeFont = TrueTypeFont(path: entry.url.path, pixelHeight: resolvedPixelHeight) else {
      return nil
    }

    self.trueTypeFont = trueTypeFont
    self.baselinePx = trueTypeFont.getBaseline()

    // Precompute conservative line metrics by scanning ASCII range
    var above: Float = 0
    var below: Float = 0

    for codepoint in 32...126 {
      if let glyphBitmap = trueTypeFont.getGlyphBitmap(for: Int32(codepoint)) {
        let glyphAbove = max(0, -Float(glyphBitmap.yoff))
        let glyphBelow = max(0, Float(glyphBitmap.yoff + glyphBitmap.height))
        above = max(above, glyphAbove)
        below = max(below, glyphBelow)
      }
    }

    self.maxAboveBaseline = above
    self.maxBelowBaseline = below
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

  /// Get the underlying TrueType font
  public func getTrueTypeFont() -> TrueTypeFont {
    return trueTypeFont
  }

  /// Measure the width of a string
  public func measureWidth(_ text: String, scale: Float = 1.0) -> Float {
    var width: Float = 0
    let scalars = Array(text.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let codepoint = Int32(scalars[i].value)
      let next: Int32? = (i + 1 < scalars.count) ? Int32(scalars[i + 1].value) : nil
      width += trueTypeFont.getAdvance(for: codepoint, next: next) * scale
      i += 1
    }

    return width
  }

  /// Get advance for a codepoint
  public func getAdvance(for codepoint: Int32, next: Int32?, scale: Float = 1.0) -> Float {
    return trueTypeFont.getAdvance(for: codepoint, next: next) * scale
  }
}
