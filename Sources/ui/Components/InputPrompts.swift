import Foundation
import Logging
import OrderedCollections

/// A UI component that displays input prompts for different input sources.
/// This is a modern replacement for the legacy InputPromptsRenderer.
public final class InputPrompts {
  /// Layout options
  public var iconSpacing: Float = 0
  public var rowSpacing: Float = 8
  public var groupSpacing: Float = 24
  public var padding: Float = 16
  public var gapBetweenIconsAndLabel: Float = 8
  /// Fine-tune vertical alignment of labels (positive moves down)
  public var labelBaselineOffset: Float = -14
  /// Target icon height in pixels. If set, icons are scaled to this height preserving aspect.
  public var targetIconHeight: Float? = 32
  /// Icon opacity (0.0 = transparent, 1.0 = opaque)
  public var iconOpacity: Float = 0.75
  /// Label color (R, G, B, A)
  public var labelColor: (Float, Float, Float, Float) = (1, 1, 1, 0.95)

  private let textStyle: TextStyle

  public init(labelFontName: String = "Creato Display Bold", labelPx: Float = 24) {
    self.textStyle = TextStyle(fontName: labelFontName, fontSize: labelPx, color: .white)
  }

  private func measureTextWidth(_ text: String) -> Float {
    // Use proper text measurement like AppKit
    return text.size(with: textStyle).width
  }

  private var lineHeight: Float {
    return textStyle.fontSize * 1.2
  }

  /// Does a single icon name match the given input source by prefix?
  @inline(__always) private func iconMatches(_ iconName: String, source: InputSource) -> Bool {
    switch source {
    case .keyboardMouse: return iconName.hasPrefix("keyboard") || iconName.hasPrefix("mouse")
    case .playstation, .xbox: return iconName.hasPrefix(source.rawValue)
    }
  }

  /// Pick the first option whose icons match the given source prefix and exist in this atlas
  @inline(__always) private func chooseIcons(for source: InputSource, from options: [[String]]) -> [String]? {
    for iconSet in options {
      var setIsRenderableForSource = true
      for iconName in iconSet {
        if !iconMatches(iconName, source: source) {
          setIsRenderableForSource = false
          break
        }
      }
      if setIsRenderableForSource { return iconSet }
    }
    return nil
  }

  /// Get the draw size for an icon, scaling to target height if specified
  @inline(__always) private func iconDrawSize(_ name: String, atlas: ImageAtlas) -> (w: Float, h: Float)? {
    guard let entry = atlas.entry(named: name) else { return nil }
    let sz = (entry.size.width, entry.size.height)
    if let h = targetIconHeight { return (sz.0 * (h / sz.1), h) }
    return (sz.0, sz.1)
  }

  /// Render a single horizontal strip of groups aligned to bottom-right.
  public func drawHorizontal(groups: [Row], windowSize: (w: Int32, h: Int32)) {
    let W = Float(windowSize.w)

    // Measure total width and max height
    var totalWidth: Float = 0
    var maxHeight: Float = 0
    for (gi, g) in groups.enumerated() {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in g.iconNames.enumerated() {
        // We need to determine which atlas to use for this icon
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let sz = iconDrawSize(name, atlas: atlas) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = measureTextWidth(g.label)
      let height = max(maxIconHeight, lineHeight)
      maxHeight = max(maxHeight, height)
      totalWidth += iconsWidth + gapBetweenIconsAndLabel + labelWidth
      if gi + 1 < groups.count { totalWidth += groupSpacing }
    }

    let startX = W - padding - totalWidth
    let y: Float = padding
    var x = startX

    for (gi, g) in groups.enumerated() {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in g.iconNames.enumerated() {
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let sz = iconDrawSize(name, atlas: atlas) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let groupHeight = max(maxIconHeight, lineHeight)
      // Per-group vertical centering inside the strip
      let groupTop = y + (maxHeight - groupHeight) * 0.5
      let iconY = groupTop + (groupHeight - maxIconHeight) * 0.5
      let labelBaselineY =
        groupTop + (groupHeight - lineHeight) * 0.5 + textStyle.fontSize * 0.8 + labelBaselineOffset

      var iconX = x
      for (i, name) in g.iconNames.enumerated() {
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let drawSize = iconDrawSize(name, atlas: atlas) {
          let dy = iconY + (maxIconHeight - drawSize.h) * 0.5
          atlas.draw(
            name: name,
            in: Rect(x: iconX, y: dy, width: drawSize.w, height: drawSize.h),
            context: GraphicsContext.current
          )
          iconX += drawSize.w
          if i + 1 < g.iconNames.count { iconX += iconSpacing }
        }
      }

      x += iconsWidth + gapBetweenIconsAndLabel
      let labelStyle = TextStyle(
        fontName: textStyle.fontName, fontSize: textStyle.fontSize,
        color: Color(red: labelColor.0, green: labelColor.1, blue: labelColor.2, alpha: labelColor.3))
      g.label.draw(at: Point(x, labelBaselineY), style: labelStyle, anchor: .baselineLeft)

      x += measureTextWidth(g.label)
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Render a horizontal strip at an explicit origin/anchor.
  /// For left anchors, `origin.x` is the left edge; for right, it's the right edge.
  /// For top anchors, `origin.y` is the top edge; for bottom, it's the bottom edge.
  public func drawHorizontal(
    groups: [Row],
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: Anchor
  ) {
    // Measure total width and max height
    var totalWidth: Float = 0
    var maxHeight: Float = 0
    struct GroupMetrics {
      let iconsWidth: Float
      let maxIconHeight: Float
      let labelWidth: Float
      let height: Float
    }
    var metrics: [GroupMetrics] = []
    for g in groups {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in g.iconNames.enumerated() {
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let sz = iconDrawSize(name, atlas: atlas) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = measureTextWidth(g.label)
      let height = max(maxIconHeight, lineHeight)
      maxHeight = max(maxHeight, height)
      totalWidth += iconsWidth + gapBetweenIconsAndLabel + labelWidth
      metrics.append(
        GroupMetrics(iconsWidth: iconsWidth, maxIconHeight: maxIconHeight, labelWidth: labelWidth, height: height))
    }
    if !groups.isEmpty { totalWidth += groupSpacing * Float(max(0, groups.count - 1)) }

    // Determine starting x based on anchor
    var x: Float = origin.x
    switch anchor {
    case .topLeft, .bottomLeft:
      x = origin.x
    case .topRight, .bottomRight:
      x = origin.x - totalWidth
    }

    // Determine base y based on anchor
    let y: Float = {
      switch anchor {
      case .bottomLeft, .bottomRight:
        return origin.y
      case .topLeft, .topRight:
        return origin.y - maxHeight
      }
    }()

    for (gi, g) in groups.enumerated() {
      let m = metrics[gi]
      let groupTop = y + (maxHeight - m.height) * 0.5
      let iconY = groupTop + (m.height - m.maxIconHeight) * 0.5
      let labelBaselineY =
        groupTop + (m.height - lineHeight) * 0.5 + textStyle.fontSize * 0.8 + labelBaselineOffset

      var iconX = x
      for (i, name) in g.iconNames.enumerated() {
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let drawSize = iconDrawSize(name, atlas: atlas) {
          let dy = iconY + (m.maxIconHeight - drawSize.h) * 0.5
          atlas.draw(
            name: name,
            in: Rect(x: iconX, y: dy, width: drawSize.w, height: drawSize.h),
            context: GraphicsContext.current
          )
          iconX += drawSize.w
          if i + 1 < g.iconNames.count { iconX += iconSpacing }
        }
      }

      x += m.iconsWidth + gapBetweenIconsAndLabel
      let labelStyle = TextStyle(
        fontName: textStyle.fontName, fontSize: textStyle.fontSize,
        color: Color(red: labelColor.0, green: labelColor.1, blue: labelColor.2, alpha: labelColor.3))
      g.label.draw(at: Point(x, labelBaselineY), style: labelStyle, anchor: .baselineLeft)
      x += m.labelWidth
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Convenience: build and draw a horizontal strip from a label→icon options matrix.
  /// For each label, chooses the first icon-set matching the provided inputSource by prefix.
  /// Dictionary iteration preserves insertion order.
  public func drawHorizontal(
    prompts: [String: [[String]]],
    inputSource: InputSource,
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: Anchor
  ) {
    var groups: [Row] = []
    for (label, options) in prompts {
      if let icons = chooseIcons(for: inputSource, from: options) {
        groups.append(Row(iconNames: icons, label: label))
      }
    }
    drawHorizontal(groups: groups, windowSize: windowSize, origin: origin, anchor: anchor)
  }

  /// Ordered overload: preserves explicit label ordering using OrderedDictionary
  public func drawHorizontal(
    prompts: OrderedDictionary<String, [[String]]>,
    inputSource: InputSource,
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: Anchor
  ) {
    var groups: [Row] = []
    for (label, options) in prompts {
      if let icons = chooseIcons(for: inputSource, from: options) {
        groups.append(Row(iconNames: icons, label: label))
      }
    }
    drawHorizontal(groups: groups, windowSize: windowSize, origin: origin, anchor: anchor)
  }

  /// Measure the actual size of a horizontal strip for the given prompts and input source
  public func measureHorizontal(
    prompts: OrderedDictionary<String, [[String]]>,
    inputSource: InputSource
  ) -> (width: Float, height: Float) {
    var groups: [Row] = []
    for (label, options) in prompts {
      if let icons = chooseIcons(for: inputSource, from: options) {
        groups.append(Row(iconNames: icons, label: label))
      }
    }

    // Measure total width and max height
    var totalWidth: Float = 0
    var maxHeight: Float = 0

    for (gi, g) in groups.enumerated() {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in g.iconNames.enumerated() {
        let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
        guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
        if let sz = iconDrawSize(name, atlas: atlas) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = measureTextWidth(g.label)
      let height = max(maxIconHeight, lineHeight)
      maxHeight = max(maxHeight, height)
      totalWidth += iconsWidth + gapBetweenIconsAndLabel + labelWidth
      if gi + 1 < groups.count { totalWidth += groupSpacing }
    }

    return (width: totalWidth, height: maxHeight)
  }
}

// MARK: - Supporting Types

extension InputPrompts {
  public struct Row {
    public let iconNames: [String]
    public let label: String
  }

  public enum Anchor {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
  }
}
