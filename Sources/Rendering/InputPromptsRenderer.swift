import Foundation
import OrderedCollections

enum InputSource: String, CaseIterable {
  case keyboardMouse
  case playstation
  case xbox
}

/// Displays input prompts + labels in the bottom-right corner using an atlas and text.
/// Example data:
///   [
///     (["playstation_button_circle"], "Confirm"),
///     (["playstation_dpad_left", "playstation_dpad_right"], "Select"),
///   ]
final class InputPromptsRenderer {
  struct Row {
    let iconNames: [String]
    let label: String
  }

  enum Anchor {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
  }

  private let text: TextRenderer
  // Atlases are selected per-icon by name prefix and loaded lazily
  private lazy var kmAtlas: AtlasImageRenderer = AtlasImageRenderer("UI/InputPrompts/keyboard-mouse.xml")
  private lazy var psAtlas: AtlasImageRenderer = AtlasImageRenderer("UI/InputPrompts/playstation.xml")
  private lazy var xbAtlas: AtlasImageRenderer = AtlasImageRenderer("UI/InputPrompts/xbox.xml")

  /// Layout options
  var iconSpacing: Float = 0
  var rowSpacing: Float = 8
  var groupSpacing: Float = 24
  var padding: Float = 16
  var gapBetweenIconsAndLabel: Float = 8
  /// Fine-tune vertical alignment of labels (positive moves down)
  var labelBaselineOffset: Float = -14
  /// Target icon height in pixels. If set, icons are scaled to this height preserving aspect.
  var targetIconHeight: Float? = 32

  @inline(__always) private func atlasForIconName(_ name: String) -> AtlasImageRenderer? {
    if name.hasPrefix("keyboard") || name.hasPrefix("mouse") { return kmAtlas }
    if name.hasPrefix("playstation") { return psAtlas }
    if name.hasPrefix("xbox") { return xbAtlas }
    return nil
  }

  @inline(__always) private func iconDrawSize(_ name: String) -> (w: Float, h: Float)? {
    guard let sz = atlasForIconName(name)?.scaledSpriteSize(name: name) else { return nil }
    if let h = targetIconHeight { return (sz.w * (h / sz.h), h) }
    return (sz.w, sz.h)
  }

  /// Does a single icon name match the given input source by prefix?
  @inline(__always) private func iconMatches(_ iconName: String, source: InputSource) -> Bool {
    switch source {
    case .keyboardMouse: iconName.hasPrefix("keyboard") || iconName.hasPrefix("mouse")
    case .playstation, .xbox: iconName.hasPrefix(source.rawValue)
    }
  }

  /// Pick the first option whose icons match the given source prefix and exist in this atlas
  @inline(__always) private func chooseIcons(for source: InputSource, from options: [[String]]) -> [String]? {
    for iconSet in options {
      var setIsRenderableForSource = true
      for iconName in iconSet {
        if !iconMatches(iconName, source: source) || iconDrawSize(iconName) == nil {
          setIsRenderableForSource = false
          break
        }
      }
      if setIsRenderableForSource { return iconSet }
    }
    return nil
  }

  init(labelFontName: String = "Creato Display Bold", labelPx: Float = 24) {
    self.text = TextRenderer(labelFontName, labelPx)!
  }

  /// Render rows aligned to bottom-right of the window.
  func draw(rows: [Row], windowSize: (w: Int32, h: Int32)) {
    let W = Float(windowSize.w)
    //    let H = Float(windowSize.h)

    // Compute total block height to start from bottom with padding
    var totalHeight: Float = 0
    for row in rows {
      let iconHeight: Float = row.iconNames.compactMap { iconDrawSize($0)?.h }.max() ?? 0
      let labelHeight = text.scaledLineHeight
      let rowHeight = max(iconHeight, labelHeight)
      totalHeight += rowHeight
    }
    if !rows.isEmpty { totalHeight += rowSpacing * Float(max(0, rows.count - 1)) }

    var y: Float = padding
    for row in rows {
      // Determine row sizes
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in row.iconNames.enumerated() {
        if let sz = iconDrawSize(name) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < row.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = text.measureWidth(row.label)
      let rowHeight = max(maxIconHeight, text.scaledLineHeight)

      // Start x position so that the whole row ends at (W - padding)
      let totalRowWidth = iconsWidth + gapBetweenIconsAndLabel + labelWidth
      var x = W - padding - totalRowWidth

      // Vertically center icons and label within row box
      let iconYOffset = (rowHeight - maxIconHeight) * 0.5
      let labelBaselineY = y + (rowHeight - text.scaledLineHeight) * 0.5 + text.baselineFromTop + labelBaselineOffset

      // Draw icons
      var iconX = x
      for (i, name) in row.iconNames.enumerated() {
        if let drawSize = iconDrawSize(name) {
          let dy = y + iconYOffset + (maxIconHeight - drawSize.h) * 0.5
          if let atlas = atlasForIconName(name) {
            atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
          }
          iconX += drawSize.w
          if i + 1 < row.iconNames.count { iconX += iconSpacing }
        }
      }

      // Draw label to the right
      x += iconsWidth + gapBetweenIconsAndLabel
      text.draw(row.label, at: (x, labelBaselineY), windowSize: windowSize, anchor: .baselineLeft)

      y += rowHeight + rowSpacing
    }
  }

  /// Render rows with explicit origin/anchor.
  /// `origin` is interpreted as:
  ///   - topLeft/topRight: top edge Y
  ///   - bottomLeft/bottomRight: bottom edge Y
  ///   - left anchors: x is left edge; right anchors: x is right edge
  func draw(
    rows: [Row],
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: Anchor
  ) {
    // Pre-measure rows
    struct RowMetrics {
      let totalWidth: Float
      let height: Float
      let iconsWidth: Float
      let maxIconHeight: Float
    }
    var metrics: [RowMetrics] = []
    var totalHeight: Float = 0
    for row in rows {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in row.iconNames.enumerated() {
        if let sz = iconDrawSize(name) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < row.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = text.measureWidth(row.label)
      let rowHeight = max(maxIconHeight, text.scaledLineHeight)
      metrics.append(
        RowMetrics(
          totalWidth: iconsWidth + gapBetweenIconsAndLabel + labelWidth, height: rowHeight, iconsWidth: iconsWidth,
          maxIconHeight: maxIconHeight))
      totalHeight += rowHeight
    }
    if !rows.isEmpty { totalHeight += rowSpacing * Float(max(0, rows.count - 1)) }

    // Compute starting y from anchor
    var y: Float = origin.y
    switch anchor {
    case .topLeft, .topRight:
      y = origin.y - totalHeight
    case .bottomLeft, .bottomRight:
      y = origin.y
    }

    for (idx, row) in rows.enumerated() {
      let m = metrics[idx]
      // Determine x based on anchor (left vs right)
      var x: Float = origin.x
      switch anchor {
      case .topRight, .bottomRight:
        x = origin.x - m.totalWidth
      case .topLeft, .bottomLeft:
        x = origin.x
      }

      // Vertical alignment within this row
      let iconYOffset = (m.height - m.maxIconHeight) * 0.5
      let labelBaselineY = y + (m.height - text.scaledLineHeight) * 0.5 + text.baselineFromTop + labelBaselineOffset

      // Draw icons left-to-right
      var iconX = x
      for (i, name) in row.iconNames.enumerated() {
        if let drawSize = iconDrawSize(name) {
          let dy = y + iconYOffset + (m.maxIconHeight - drawSize.h) * 0.5
          if let atlas = atlasForIconName(name) {
            atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
          }
          iconX += drawSize.w
          if i + 1 < row.iconNames.count { iconX += iconSpacing }
        }
      }

      // Draw label
      x += m.iconsWidth + gapBetweenIconsAndLabel
      text.draw(row.label, at: (x, labelBaselineY), windowSize: windowSize, anchor: .baselineLeft)

      y += m.height + rowSpacing
    }
  }

  /// Render a single horizontal strip of groups aligned to bottom-right.
  func drawHorizontal(groups: [Row], windowSize: (w: Int32, h: Int32)) {
    let W = Float(windowSize.w)
    //    let H = Float(windowSize.h)

    // Measure total width and max height
    var totalWidth: Float = 0
    var maxHeight: Float = 0
    for (gi, g) in groups.enumerated() {
      var iconsWidth: Float = 0
      var maxIconHeight: Float = 0
      for (i, name) in g.iconNames.enumerated() {
        if let sz = iconDrawSize(name) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = text.measureWidth(g.label)
      let height = max(maxIconHeight, text.scaledLineHeight)
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
        if let sz = iconDrawSize(name) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let groupHeight = max(maxIconHeight, text.scaledLineHeight)
      // Per-group vertical centering inside the strip
      let groupTop = y + (maxHeight - groupHeight) * 0.5
      let iconY = groupTop + (groupHeight - maxIconHeight) * 0.5
      let labelBaselineY =
        groupTop + (groupHeight - text.scaledLineHeight) * 0.5 + text.baselineFromTop + labelBaselineOffset

      var iconX = x
      for (i, name) in g.iconNames.enumerated() {
        if let drawSize = iconDrawSize(name) {
          let dy = iconY + (maxIconHeight - drawSize.h) * 0.5
          if let atlas = atlasForIconName(name) {
            atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
          }
          iconX += drawSize.w
          if i + 1 < g.iconNames.count { iconX += iconSpacing }
        }
      }

      x += iconsWidth + gapBetweenIconsAndLabel
      text.draw(g.label, at: (x, labelBaselineY), windowSize: windowSize, anchor: .baselineLeft)

      x += text.measureWidth(g.label)
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Render a horizontal strip at an explicit origin/anchor.
  /// For left anchors, `origin.x` is the left edge; for right, it's the right edge.
  /// For top anchors, `origin.y` is the top edge; for bottom, it's the bottom edge.
  func drawHorizontal(
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
        if let sz = iconDrawSize(name) {
          iconsWidth += sz.w
          maxIconHeight = max(maxIconHeight, sz.h)
          if i + 1 < g.iconNames.count { iconsWidth += iconSpacing }
        }
      }
      let labelWidth = text.measureWidth(g.label)
      let height = max(maxIconHeight, text.scaledLineHeight)
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
        groupTop + (m.height - text.scaledLineHeight) * 0.5 + text.baselineFromTop + labelBaselineOffset

      var iconX = x
      for (i, name) in g.iconNames.enumerated() {
        if let drawSize = iconDrawSize(name) {
          let dy = iconY + (m.maxIconHeight - drawSize.h) * 0.5
          if let atlas = atlasForIconName(name) {
            atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
          }
          iconX += drawSize.w
          if i + 1 < g.iconNames.count { iconX += iconSpacing }
        }
      }

      x += m.iconsWidth + gapBetweenIconsAndLabel
      text.draw(g.label, at: (x, labelBaselineY), windowSize: windowSize, anchor: .baselineLeft)
      x += m.labelWidth
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Convenience: build and draw a horizontal strip from a label→icon options matrix.
  /// For each label, chooses the first icon-set matching the provided inputSource by prefix.
  /// Dictionary iteration preserves insertion order.
  func drawHorizontal(
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
  func drawHorizontal(
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
}
