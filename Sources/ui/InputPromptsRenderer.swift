import Foundation

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

  private let atlas: AtlasImageRenderer
  private let text: TextRenderer

  /// Layout options
  var iconSpacing: Float = 8
  var rowSpacing: Float = 8
  var groupSpacing: Float = 24
  var padding: Float = 16
  var gapBetweenIconsAndLabel: Float = 12
  /// Fine-tune vertical alignment of labels (positive moves down)
  var labelBaselineOffset: Float = 0
  /// Target icon height in pixels. If set, icons are scaled to this height preserving aspect.
  var targetIconHeight: Float? = 32

  @inline(__always) private func iconDrawSize(_ name: String) -> (w: Float, h: Float)? {
    guard let sz = atlas.scaledSpriteSize(name: name) else { return nil }
    if let h = targetIconHeight { return (sz.w * (h / sz.h), h) }
    return (sz.w, sz.h)
  }

  init(atlas: AtlasImageRenderer, labelFontName: String = "Determination", labelPx: Float = 24) {
    self.atlas = atlas
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
          atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
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
          atlas.drawScaled(name: name, x: iconX, y: dy, windowSize: windowSize, targetSize: (drawSize.w, drawSize.h))
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
}
