import Foundation

/// Legacy TextRenderer - compatibility wrapper for the new modular system
public final class TextRenderer {
  private let newRenderer: ModularTextRenderer

  /// Global scale factor applied at draw time (acts like em scale)
  public var scale: Float {
    get { newRenderer.scale }
    set { newRenderer.scale = newValue }
  }

  public enum Anchor {
    case topLeft
    case bottomLeft
    case baselineLeft
  }

  public init?(_ name: String, _ pixelHeight: Float? = nil) {
    guard let renderer = ModularTextRenderer(fontName: name, pixelHeight: pixelHeight) else {
      return nil
    }
    self.newRenderer = renderer
  }

  /// Line height with `scale` applied
  public var scaledLineHeight: Float { newRenderer.scaledLineHeight }

  /// Baseline offset from the top of the line box (useful for aligning mixed sizes).
  public var baselineFromTop: Float { newRenderer.baselineFromTop }

  /// Distance below the baseline to the deepest descender encountered.
  public var descentFromBaseline: Float { newRenderer.descentFromBaseline }

  /// Rough single-line width measurement at current scale for ASCII text.
  /// Uses font advances without kerning beyond next-codepoint coupling.
  public func measureWidth(_ text: String) -> Float {
    return newRenderer.measureWidth(text)
  }

  public func draw(
    _ text: String, at origin: (x: Float, y: Float), windowSize: (w: Int32, h: Int32),
    color: (Float, Float, Float, Float) = (1, 1, 1, 1),
    scale overrideScale: Float? = nil,
    wrapWidth: Float? = nil,
    anchor: Anchor = .topLeft,
    outlineColor: (Float, Float, Float, Float)? = nil,
    outlineThickness: Float = 0.0
  ) {
    let modularAnchor: ModularTextRenderer.Anchor = {
      switch anchor {
      case .topLeft: return .topLeft
      case .bottomLeft: return .bottomLeft
      case .baselineLeft: return .baselineLeft
      }
    }()

    newRenderer.draw(
      text,
      at: origin,
      windowSize: windowSize,
      color: color,
      scale: overrideScale,
      wrapWidth: wrapWidth,
      anchor: modularAnchor,
      outlineColor: outlineColor,
      outlineThickness: outlineThickness
    )
  }
}
