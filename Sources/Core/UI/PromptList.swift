import Foundation
import Logging
import OrderedCollections

/// A UI component that displays input prompts for different input sources.
/// This is a modern replacement for the legacy InputPromptsRenderer.
public final class PromptList {
  /// Layout options
  public var iconSpacing: Float = 0
  public var rowSpacing: Float = 8
  public var groupSpacing: Float = 24
  public var padding: Float = 16
  public var gapBetweenIconsAndLabel: Float = 8
  /// Fine-tune vertical alignment of labels (positive moves down)
  public var labelBaselineOffset: Float = -14
  /// Target icon height in pixels. If set, icons are scaled to this height preserving aspect.
  public var targetIconHeight: Float? = 40
  /// Icon opacity (0.0 = transparent, 1.0 = opaque)
  public var iconOpacity: Float = 0.5
  /// Label color (R, G, B, A)
  public var labelColor: (Float, Float, Float, Float) = (1, 1, 1, 0.6)

  private let textStyle: TextStyle
  public var group: PromptGroup?
  public var axis: Axis
  public var showCalloutBackground: Bool = false

  public init(_ group: PromptGroup? = nil, axis: Axis = .horizontal) {
    self.textStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 24, color: .white)
    self.group = group
    self.axis = axis
  }

  private func measureTextWidth(_ text: String) -> Float {
    // Use proper text measurement like AppKit
    return text.size(with: textStyle).width
  }

  private var lineHeight: Float {
    return textStyle.fontSize * 1.2
  }

  /// Computed size of the prompt list based on current group and axis
  @MainActor public var size: Size {
    guard let group = group else { return Size.zero }
    let prompts = PromptGroup.prompts[group] ?? [:]
    return size(for: prompts, inputSource: .player1)
  }

  /// Calculate size for given prompts and input source
  public func size(for prompts: OrderedDictionary<String, [[String]]>, inputSource: InputSource = .player1) -> Size {
    var groups: [Row] = []
    for (label, options) in prompts {
      if let icons = chooseIcons(for: inputSource, from: options) {
        groups.append(Row(iconNames: icons, label: label))
      }
    }

    let (totalWidth, maxHeight, _) = calculateTotalMetrics(groups)

    switch axis {
    case .horizontal:
      return Size(totalWidth, maxHeight)
    case .vertical:
      let totalHeight = maxHeight + Float(max(0, groups.count - 1)) * rowSpacing
      return Size(Float(Engine.viewportSize.width) / 3, totalHeight)  // Use same width as vertical layout
    }
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

  /// Calculate metrics for a single group
  private func calculateGroupMetrics(_ group: Row) -> (
    iconsWidth: Float, maxIconHeight: Float, labelWidth: Float, height: Float
  ) {
    var iconsWidth: Float = 0
    var maxIconHeight: Float = 0
    for (i, name) in group.iconNames.enumerated() {
      let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
      guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
      if let sz = iconDrawSize(name, atlas: atlas) {
        iconsWidth += sz.w
        maxIconHeight = max(maxIconHeight, sz.h)
        if i + 1 < group.iconNames.count { iconsWidth += iconSpacing }
      }
    }
    let labelWidth = measureTextWidth(group.label)
    let height = max(maxIconHeight, lineHeight)
    return (iconsWidth: iconsWidth, maxIconHeight: maxIconHeight, labelWidth: labelWidth, height: height)
  }

  /// Calculate total metrics for all groups
  private func calculateTotalMetrics(_ groups: [Row]) -> (
    totalWidth: Float, maxHeight: Float,
    groupMetrics: [(iconsWidth: Float, maxIconHeight: Float, labelWidth: Float, height: Float)]
  ) {
    var totalWidth: Float = 0
    var maxHeight: Float = 0
    var groupMetrics: [(iconsWidth: Float, maxIconHeight: Float, labelWidth: Float, height: Float)] = []

    for (gi, group) in groups.enumerated() {
      let metrics = calculateGroupMetrics(group)
      groupMetrics.append(metrics)
      maxHeight = max(maxHeight, metrics.height)
      totalWidth += metrics.iconsWidth + gapBetweenIconsAndLabel + metrics.labelWidth
      if gi + 1 < groups.count { totalWidth += groupSpacing }
    }

    return (totalWidth: totalWidth, maxHeight: maxHeight, groupMetrics: groupMetrics)
  }

  /// Render a single group at the given position.
  private func drawGroup(
    _ group: Row, metrics: (iconsWidth: Float, maxIconHeight: Float, labelWidth: Float, height: Float),
    at position: (x: Float, y: Float), maxHeight: Float
  ) {
    let groupTop = position.y + (maxHeight - metrics.height) * 0.5
    let iconY = groupTop + (metrics.height - metrics.maxIconHeight) * 0.5
    let labelBaselineY = groupTop + (metrics.height - lineHeight) * 0.5 + textStyle.fontSize * 0.9 + labelBaselineOffset

    var iconX = position.x
    for (i, name) in group.iconNames.enumerated() {
      let source = InputSource.detect(fromIconName: name) ?? .keyboardMouse
      guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }
      if let drawSize = iconDrawSize(name, atlas: atlas) {
        let dy = iconY + (metrics.maxIconHeight - drawSize.h) * 0.5
        atlas.draw(
          name: name,
          in: Rect(x: iconX, y: dy, width: drawSize.w, height: drawSize.h),
          tint: .white.withAlphaComponent(iconOpacity),
          context: GraphicsContext.current
        )
        iconX += drawSize.w
        if i + 1 < group.iconNames.count { iconX += iconSpacing }
      }
    }

    let labelX = position.x + metrics.iconsWidth + gapBetweenIconsAndLabel
    let labelStyle = TextStyle(
      fontName: textStyle.fontName, fontSize: textStyle.fontSize,
      color: Color(red: labelColor.0, green: labelColor.1, blue: labelColor.2, alpha: labelColor.3))
    group.label.draw(at: Point(labelX, labelBaselineY), style: labelStyle, anchor: .baselineLeft)
  }

  /// Render a single horizontal strip of groups aligned to bottom-right.
  private func drawHorizontal(groups: [Row], windowSize: (w: Int32, h: Int32)) {
    let W = Float(windowSize.w)
    let (totalWidth, maxHeight, groupMetrics) = calculateTotalMetrics(groups)

    let startX = W - padding - totalWidth
    let y: Float = padding
    var x = startX

    for (gi, group) in groups.enumerated() {
      let metrics = groupMetrics[gi]
      drawGroup(group, metrics: metrics, at: (x: x, y: y), maxHeight: maxHeight)
      x += metrics.iconsWidth + gapBetweenIconsAndLabel + metrics.labelWidth
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Render a horizontal strip at an explicit origin/anchor.
  /// For left anchors, `origin.x` is the left edge; for right, it's the right edge.
  /// For top anchors, `origin.y` is the top edge; for bottom, it's the bottom edge.
  private func drawHorizontal(
    groups: [Row],
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: AnchorPoint
  ) {
    let (totalWidth, maxHeight, groupMetrics) = calculateTotalMetrics(groups)

    // Determine starting x based on anchor
    var x: Float = origin.x
    switch anchor {
    case .topLeft, .bottomLeft:
      x = origin.x
    case .top, .bottom:
      x = origin.x - totalWidth / 2
    case .topRight, .bottomRight:
      x = origin.x - totalWidth
    case .left:
      x = origin.x
    case .center:
      x = origin.x - totalWidth / 2
    case .right:
      x = origin.x - totalWidth
    case .baselineLeft:
      x = origin.x
    }

    // Determine base y based on anchor
    let y: Float = {
      switch anchor {
      case .bottomLeft, .bottomRight:
        return origin.y
      case .topLeft, .topRight:
        return origin.y - maxHeight
      case .left, .right:
        return origin.y - maxHeight / 2
      case .top, .bottom:
        return origin.y - maxHeight / 2
      case .center:
        return origin.y - maxHeight / 2
      case .baselineLeft:
        return origin.y
      }
    }()

    for (gi, group) in groups.enumerated() {
      let metrics = groupMetrics[gi]
      drawGroup(group, metrics: metrics, at: (x: x, y: y), maxHeight: maxHeight)
      x += metrics.iconsWidth + gapBetweenIconsAndLabel + metrics.labelWidth
      if gi + 1 < groups.count { x += groupSpacing }
    }
  }

  /// Convenience: build and draw a horizontal strip from a label→icon options matrix.
  /// For each label, chooses the first icon-set matching the provided inputSource by prefix.
  /// Dictionary iteration preserves insertion order.
  private func drawHorizontal(
    prompts: [String: [[String]]],
    inputSource: InputSource,
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: AnchorPoint
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
    inputSource: InputSource = .player1,
    windowSize: (w: Int32, h: Int32),
    origin: (x: Float, y: Float),
    anchor: AnchorPoint
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

    let (totalWidth, maxHeight, _) = calculateTotalMetrics(groups)
    return (width: totalWidth, height: maxHeight)
  }

  /// Render a vertical stack of groups
  private func drawVertical(
    groups: [Row], windowSize: (w: Int32, h: Int32), origin: (x: Float, y: Float), anchor: AnchorPoint
  ) {
    let (_, maxHeight, groupMetrics) = calculateTotalMetrics(groups)

    // Calculate total height including spacing
    let totalHeight = maxHeight + Float(max(0, groups.count - 1)) * rowSpacing

    // Determine starting position based on anchor
    let startY: Float = {
      switch anchor {
      case .topLeft, .topRight:
        return origin.y
      case .bottomLeft, .bottomRight:
        return origin.y - totalHeight
      case .left, .right:
        return origin.y - totalHeight / 2
      case .top, .bottom:
        return origin.y - totalHeight / 2
      case .center:
        return origin.y - totalHeight / 2
      case .baselineLeft:
        return origin.y
      }
    }()

    let startX: Float = {
      switch anchor {
      case .topLeft, .bottomLeft:
        return origin.x
      case .topRight, .bottomRight:
        return origin.x - Float(Engine.viewportSize.width) / 3  // Use same width as horizontal
      case .left, .right:
        return origin.x - Float(Engine.viewportSize.width) / 6
      case .top, .bottom:
        return origin.x - Float(Engine.viewportSize.width) / 6
      case .center:
        return origin.x - Float(Engine.viewportSize.width) / 6
      case .baselineLeft:
        return origin.x
      }
    }()

    var currentY = startY
    for (gi, group) in groups.enumerated() {
      let metrics = groupMetrics[gi]
      drawGroup(group, metrics: metrics, at: (x: startX, y: currentY), maxHeight: maxHeight)
      currentY += maxHeight + rowSpacing
    }
  }

  /// Draw at specific coordinates
  public func draw(
    prompts: OrderedDictionary<String, [[String]]>,
    inputSource: InputSource = .player1,
    origin: Point,
    anchor: AnchorPoint
  ) {
    let windowSize = (Int32(Engine.viewportSize.width), Int32(Engine.viewportSize.height))
    var groups: [Row] = []
    for (label, options) in prompts {
      if let icons = chooseIcons(for: inputSource, from: options) {
        groups.append(Row(iconNames: icons, label: label))
      }
    }

    switch axis {
    case .horizontal:
      drawHorizontal(groups: groups, windowSize: windowSize, origin: (origin.x, origin.y), anchor: anchor)
    case .vertical:
      drawVertical(groups: groups, windowSize: windowSize, origin: (origin.x, origin.y), anchor: anchor)
    }
  }

  /// Draw with default bottom-right positioning (convenience)
  @MainActor public func draw() {
    guard let group = group else { return }
    let prompts = PromptGroup.prompts[group] ?? [:]
    let origin = Point(Float(Engine.viewportSize.width) - 56, 12)

    // Draw callout background if enabled
    if showCalloutBackground {
      let promptSize = size(for: prompts, inputSource: .player1)
      let calloutWidth = promptSize.width + 128
      var callout = Callout(style: .promptList(width: calloutWidth))
      callout.draw()
    }

    // Draw the prompt list
    draw(
      prompts: prompts,
      inputSource: .player1,
      origin: origin,
      anchor: .bottomRight
    )
  }
}

// MARK: - Supporting Types

extension PromptList {
  public struct Row {
    public let iconNames: [String]
    public let label: String
  }

  // PromptList.Anchor has been replaced with the centralized Alignment enum in Geometry.swift
}
