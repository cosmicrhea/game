import Foundation

/// A single input prompt that can render just an icon without text.
/// Usage: Prompt([["keyboard_tab_icon"], ["xbox_button_color_x"], ["playstation_button_color_square"]])
public final class Prompt {
  /// The icon options for different input sources
  public let iconOptions: [[String]]

  /// Target icon height in pixels. If set, icons are scaled to this height preserving aspect.
  public var targetIconHeight: Float? = 40

  /// Icon opacity (0.0 = transparent, 1.0 = opaque)
  public var iconOpacity: Float = 0.5

  /// Spacing between multiple icons in the same prompt
  public var iconSpacing: Float = 0

  public init(_ iconOptions: [[String]]) {
    self.iconOptions = iconOptions
  }

  /// Get the size of the prompt icon(s) for the given input source
  public func size(for inputSource: InputSource = .player1) -> Size {
    guard let icons = chooseIcons(for: inputSource) else { return Size.zero }

    var totalWidth: Float = 0
    var maxHeight: Float = 0

    for (i, iconName) in icons.enumerated() {
      let source = InputSource.detect(fromIconName: iconName) ?? .keyboardMouse
      guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }

      if let drawSize = iconDrawSize(iconName, atlas: atlas) {
        totalWidth += drawSize.w
        maxHeight = max(maxHeight, drawSize.h)
        if i + 1 < icons.count { totalWidth += iconSpacing }
      }
    }

    return Size(totalWidth, maxHeight)
  }

  /// Draw the prompt icon(s) at the specified position
  public func draw(at position: Point, inputSource: InputSource = .player1, alignment: Alignment = .topLeft) {
    guard let icons = chooseIcons(for: inputSource) else { return }

    let promptSize = size(for: inputSource)
    let adjustedPosition = adjustPosition(position, for: promptSize, alignment: alignment)

    var iconX = adjustedPosition.x
    let iconY = adjustedPosition.y

    for (i, iconName) in icons.enumerated() {
      let source = InputSource.detect(fromIconName: iconName) ?? .keyboardMouse
      guard let atlas = ImageAtlas.loadInputPromptsAtlas(for: source) else { continue }

      if let drawSize = iconDrawSize(iconName, atlas: atlas) {
        let dy = iconY + (promptSize.height - drawSize.h) * 0.5
        atlas.draw(
          name: iconName,
          in: Rect(x: iconX, y: dy, width: drawSize.w, height: drawSize.h),
          tint: .white.withAlphaComponent(iconOpacity),
          context: GraphicsContext.current
        )
        iconX += drawSize.w
        if i + 1 < icons.count { iconX += iconSpacing }
      }
    }
  }

  // MARK: - Private Helpers

  /// Pick the first option whose icons match the given source prefix
  private func chooseIcons(for source: InputSource) -> [String]? {
    for iconSet in iconOptions {
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

  /// Does a single icon name match the given input source by prefix?
  private func iconMatches(_ iconName: String, source: InputSource) -> Bool {
    switch source {
    case .keyboardMouse: return iconName.hasPrefix("keyboard") || iconName.hasPrefix("mouse")
    case .playstation, .xbox: return iconName.hasPrefix(source.rawValue)
    }
  }

  /// Get the draw size for an icon, scaling to target height if specified
  private func iconDrawSize(_ name: String, atlas: ImageAtlas) -> (w: Float, h: Float)? {
    guard let entry = atlas.entry(named: name) else { return nil }
    let sz = (entry.size.width, entry.size.height)
    if let h = targetIconHeight { return (sz.0 * (h / sz.1), h) }
    return (sz.0, sz.1)
  }

  /// Adjust position based on alignment
  private func adjustPosition(_ position: Point, for size: Size, alignment: Alignment) -> Point {
    switch alignment {
    case .topLeft:
      return position
    case .top:
      return Point(position.x - size.width * 0.5, position.y)
    case .topRight:
      return Point(position.x - size.width, position.y)
    case .left:
      return Point(position.x, position.y - size.height * 0.5)
    case .center:
      return Point(position.x - size.width * 0.5, position.y - size.height * 0.5)
    case .right:
      return Point(position.x - size.width, position.y - size.height * 0.5)
    case .bottomLeft:
      return Point(position.x, position.y - size.height)
    case .bottom:
      return Point(position.x - size.width * 0.5, position.y - size.height)
    case .bottomRight:
      return Point(position.x - size.width, position.y - size.height)
    case .baselineLeft:
      return position
    }
  }
}
