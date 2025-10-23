/// Available icon types for callouts.
public enum CalloutIcon: String, CaseIterable {
  /// A chevron arrow icon.
  case chevron
  /// An information icon.
  case info
  /// A location/map pin icon.
  case location
}

/// Semantic callout styles for different use cases.
public enum CalloutStyle {
  /// Objective callout - top-left with Y offset for stacking
  case objective(offset: Float = 0)
  /// Tutorial callout - centered on screen
  case tutorial
  /// Prompt list callout - bottom-right with custom width
  case promptList(width: Float = Engine.viewportSize.width / 3)
  /// Item description - bottom-ish-right
  case itemDescription
  /// Item description - bottom-ish-left
  case healthDisplay
}

/// Fade effect options for callout edges.
public enum CalloutFade {
  /// No fade effect.
  case none
  /// Fade from left edge.
  case left
  /// Fade from right edge.
  case right
  /// Fade from both edges.
  case both
}

/// A UI callout component that displays text and optional icons with animated transitions.
public class Callout {
  // Content
  /// The text content to display in the callout.
  public var text: String
  /// Optional icon to display alongside the text.
  public var icon: CalloutIcon?

  // Layout/appearance
  /// Style of the callout determining position and behavior.
  public var style: CalloutStyle = .objective()
  /// Fade effect applied to the callout edges.
  public var fade: CalloutFade = .right
  /// Ratio of the callout width used for fade effects (0.0 to 1.0).
  public var fadeWidthRatio: Float = 1 / 3
  /// Horizontal padding between the callout edge and icon.
  public var iconPaddingX: Float = 48
  /// Gap between icon and text content.
  public var iconTextGap: Float = 8
  /// Color tint applied to the icon.
  public var iconColor: Color = Color(0.6, 0.6, 0.6, 1)
  /// Color of the text label.
  public var labelColor: Color = Color(0.9, 0.9, 0.9, 1)

  // Visibility
  /// Whether the callout is visible; triggers animation when changed.
  public var visible: Bool = true { didSet { targetVisible = visible } }

  // Animation state (spring)
  private var targetVisible: Bool = true
  private var animationProgress: Float = 1.0
  private var animationVelocity: Float = 0.0
  private let springStiffness: Float = 2.5
  private let springDamping: Float = 0.8
  private let animationSpeed: Float = 7.0

  // Effects and caches
  private let effect = GLScreenEffect("effects/callout")
  private var cachedIcon: Image?

  // Default style for callouts (hardcoded)
  private static let defaultStyle = TextStyle(
    fontName: "CreatoDisplay-Bold",
    fontSize: 20,
    color: Color(0.9, 0.9, 0.9, 1)
  )

  /// Creates a new callout with the specified text and optional icon.
  /// - Parameters:
  ///   - text: The text content to display.
  ///   - icon: Optional icon to display alongside the text.
  ///   - style: The callout style determining position and behavior.
  public init(_ text: String = "", icon: CalloutIcon? = nil, style: CalloutStyle = .objective()) {
    self.text = text
    self.icon = icon
    self.style = style
    self.visible = true
    self.targetVisible = true
    self.animationProgress = 1
  }

  /// Computed size of the callout for future multi-line support.
  public var size: Size {
    let textWidth = text.size(with: Callout.defaultStyle).width
    let iconWidth: Float = icon != nil ? 20 + iconTextGap : 0
    let totalWidth = iconWidth + textWidth + iconPaddingX * 2
    return Size(totalWidth, 36)
  }

  /// Updates the callout's animation state for the current frame.
  /// - Parameter deltaTime: Time elapsed since the last frame in seconds.
  @MainActor public func update(deltaTime: Float) {
    let target: Float = targetVisible ? 1 : 0
    let springForce = (target - animationProgress) * springStiffness
    let dampingForce = -animationVelocity * springDamping
    let acceleration = springForce + dampingForce
    animationVelocity += acceleration * deltaTime * animationSpeed
    animationProgress += animationVelocity * deltaTime * animationSpeed
    animationProgress = max(0, min(1, animationProgress))
    if abs(target - animationProgress) < 0.001 && abs(animationVelocity) < 0.001 {
      animationProgress = target
      animationVelocity = 0
    }
  }

  /// Draws the callout using its style to determine position and behavior.
  /// - Parameter context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  @MainActor public func draw(context: GraphicsContext? = nil) {
    // Update icon cache if needed
    if cachedIcon == nil, let icon = icon, let path = iconResourcePath(icon) {
      cachedIcon = Image(path)
    }

    // Early out if fully hidden
    if !visible && animationProgress <= 0 { return }

    // Determine position and rect based on style
    let (rect, fade): (Rect, CalloutFade) = {
      switch style {
      case .objective(let offset):
        let w = Float(Engine.viewportSize.width) / 3
        let h: Float = 36
        let topMargin: Float = 128
        let origin = Point(0, Float(Engine.viewportSize.height) - h - topMargin - offset)
        return (Rect(origin: origin, size: Size(w, h)), .right)
      case .tutorial:
        let w = Float(Engine.viewportSize.width) / 3
        let h: Float = 36
        let origin = Point(
          Float(Engine.viewportSize.width) * 0.5 - w * 0.5,
          Float(Engine.viewportSize.height) * 0.5 - h * 0.5 - 128)
        return (Rect(origin: origin, size: Size(w, h)), .both)
      case .promptList(let width):
        let w = width
        let h: Float = 57
        let origin = Point(Float(Engine.viewportSize.width) - w, 0)
        return (Rect(origin: origin, size: Size(w, h)), .left)
      case .itemDescription:
        let w: Float = 480
        let h: Float = 128
        let origin = Point(Engine.viewportSize.width - w, 96)
        return (Rect(origin: origin, size: Size(w, h)), .left)
      case .healthDisplay:
        let w: Float = 128 + 44 * 2
        let h: Float = 128 + 24
        let origin = Point(0, 96)
        return (Rect(origin: origin, size: Size(w, h)), .right)
      }
    }()

    // Compute base center
    let px = rect.origin.x
    let py = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height
    let baseCenter = (px + w * 0.5, py + h * 0.5)

    // Configure fades
    let fadeWidth: Float = {
      switch style {
      case .promptList, .itemDescription, .healthDisplay:
        return 50.0  // Fixed 50px fade for prompt list & item description
      case .objective, .tutorial:
        return max(0, fadeWidthRatio) * w  // Use ratio for other styles
      }
    }()
    let leftWidth: Float = (fade == .left || fade == .both) ? fadeWidth : -1.0
    let rightWidth: Float = (fade == .right || fade == .both) ? fadeWidth : -1.0

    // Draw background via screen effect (uses GL under the hood)
    effect.draw { program in
      program.setVec2("uRectSize", value: (w, h))
      program.setVec2("uRectCenter", value: (baseCenter.0, baseCenter.1))
      program.setFloat("uLeftFadeWidth", value: leftWidth)
      program.setFloat("uRightFadeWidth", value: rightWidth)
      program.setFloat("uAnimationAlpha", value: animationProgress)

      // Control border drawing based on style
      let drawBorders: Float =
        switch style {
        case .objective, .tutorial: 1.0
        case .promptList, .itemDescription: 1.0
        case .healthDisplay: 1.0
        }

      program.setFloat("uDrawBorders", value: drawBorders)
    }

    // Content layout with slide animation (only for objectives)
    let left = baseCenter.0 - w * 0.5
    let slideDistance: Float = w * 0.1
    let animatedContentX: Float = {
      switch style {
      case .objective:
        // Apply slide animation for objectives
        return left + iconPaddingX - slideDistance * (1.0 - animationProgress)
      case .tutorial, .promptList, .itemDescription, .healthDisplay:
        // No slide animation for other styles
        return left + iconPaddingX
      }
    }()
    var contentX = animatedContentX

    // Icon (skip for promptList style)
    if case .promptList = style {
      // Skip icon for promptList
    } else if let iconImage = cachedIcon {
      let iconSize: Size = Size(20, 20)
      let iconRect = Rect(
        x: contentX,
        y: baseCenter.1 - iconSize.height * 0.5,
        width: iconSize.width,
        height: iconSize.height
      )
      // Apply animation alpha to icon
      let iconTint = Color(1.0, 1.0, 1.0, animationProgress)
      iconImage.draw(in: iconRect, tint: iconTint, context: context)
      contentX += iconSize.width + iconTextGap
    }

    // Label positioning based on style
    let lineTopY = baseCenter.1 + Callout.defaultStyle.fontSize * 0.5
    var labelPoint: Point
    var labelStyle = Callout.defaultStyle
    labelStyle.color.alpha *= animationProgress

    switch style {
    case .tutorial:
      // Center the text within the callout
      let textWidth = text.size(with: labelStyle).width
      let totalContentWidth = (cachedIcon != nil ? 20 + iconTextGap : 0) + textWidth
      let contentStartX = baseCenter.0 - totalContentWidth * 0.5
      let textX = contentStartX + (cachedIcon != nil ? 20 + iconTextGap : 0)
      labelPoint = Point(textX, lineTopY)
    case .objective, .promptList, .itemDescription, .healthDisplay:
      // Use the existing left-aligned positioning
      labelPoint = Point(contentX, lineTopY)
    }

    // Don't draw text for promptList style
    if case .promptList = style {
      // Skip text for promptList
    } else if case .itemDescription = style {
      // Ditto
    } else if case .healthDisplay = style {
      // Ditto
    } else {
      text.draw(at: labelPoint, style: labelStyle, context: context)
    }
  }

  private func iconResourcePath(_ icon: CalloutIcon) -> String? {
    switch icon {
    case .chevron: return "UI/Icons/callouts/chevron.png"
    case .info: return "UI/Icons/callouts/info.png"
    case .location: return "UI/Icons/callouts/location.png"
    }
  }
}
