import GL

/// Available icon types for callouts.
public enum CalloutIcon: String, CaseIterable {
  /// A chevron arrow icon.
  case chevron
  /// An information icon.
  case info
  /// A location/map pin icon.
  case location
}

/// Positioning options for callouts.
public enum CalloutPosition {
  /// Position at the top-left of the target area with optional Y offset.
  case topLeft(yOffset: Float = 0)
  /// Position at the center of the target area with optional Y offset.
  case center(yOffset: Float = -128)
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
public struct Callout {
  // Content
  /// The text content to display in the callout.
  public var text: String
  /// Optional icon to display alongside the text.
  public var icon: CalloutIcon?

  // Layout/appearance
  /// Position of the callout relative to its target area.
  public var position: CalloutPosition = .topLeft()
  /// Fade effect applied to the callout edges.
  public var fade: CalloutFade = .right
  /// Ratio of the callout width used for fade effects (0.0 to 1.0).
  public var fadeWidthRatio: Float = 1.0 / 3.0
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
    fontName: "Creato Display Bold",
    fontSize: 20,
    color: Color(0.9, 0.9, 0.9, 1)
  )

  /// Creates a new callout with the specified text and optional icon.
  /// - Parameters:
  ///   - text: The text content to display.
  ///   - icon: Optional icon to display alongside the text.
  public init(_ text: String, icon: CalloutIcon? = nil) {
    self.text = text
    self.icon = icon
    self.visible = true
    self.targetVisible = true
    self.animationProgress = 1
  }

  /// Updates the callout's animation state for the current frame.
  /// - Parameter deltaTime: Time elapsed since the last frame in seconds.
  @MainActor public mutating func update(deltaTime: Float) {
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

  /// Draws the callout within the specified rectangle.
  /// - Parameters:
  ///   - rect: The rectangle to draw the callout within.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  @MainActor public mutating func draw(in rect: Rect, context: GraphicsContext? = nil) {
    // Update icon cache if needed
    if cachedIcon == nil, let icon = icon, let path = iconResourcePath(icon) {
      cachedIcon = Image(path)
    }

    // Early out if fully hidden
    if !visible && animationProgress <= 0 { return }

    // Compute base center by anchor
    let px = rect.origin.x
    let py = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    let baseCenter: (x: Float, y: Float) = {
      switch position {
      case .topLeft(let yOffset):
        return (px + w * 0.5, py - h * 0.5 + yOffset - 180)
      case .center(let yOffset):
        return (px, py + yOffset)
      }
    }()

    // Configure fades
    let fadeWidth = max(0, fadeWidthRatio) * w
    let leftWidth: Float = (fade == .left || fade == .both) ? fadeWidth : 0
    let rightWidth: Float = (fade == .right || fade == .both) ? fadeWidth : 0

    // Draw background via screen effect (uses GL under the hood)
    effect.draw { program in
      program.setVec2("uRectSize", value: (w, h))
      program.setVec2("uRectCenter", value: (baseCenter.x, baseCenter.y))
      if leftWidth > 0 { program.setFloat("uLeftFadeWidth", value: leftWidth) }
      if rightWidth > 0 { program.setFloat("uRightFadeWidth", value: rightWidth) }
      program.setFloat("uAnimationAlpha", value: animationProgress)
    }

    // Content layout with slide animation (only for non-centered callouts)
    let left = baseCenter.x - w * 0.5
    let slideDistance: Float = w * 0.1
    let animatedContentX: Float = {
      switch position {
      case .center:
        // No slide animation for centered callouts
        return left + iconPaddingX
      case .topLeft:
        // Apply slide animation for top-left positioned callouts
        return left + iconPaddingX - slideDistance * (1.0 - animationProgress)
      }
    }()
    var contentX = animatedContentX

    // Icon
    if let iconImage = cachedIcon {
      let iconSize: Size = Size(20, 20)
      let iconRect = Rect(
        x: contentX,
        y: baseCenter.y - iconSize.height * 0.5,
        width: iconSize.width,
        height: iconSize.height
      )
      iconImage.draw(in: iconRect, context: context)
      contentX += iconSize.width + iconTextGap
    }

    // Label positioning based on callout position
    let lineTopY = baseCenter.y + Callout.defaultStyle.fontSize * 0.5
    var labelPoint: Point
    var labelStyle = Callout.defaultStyle
    labelStyle.color.alpha *= animationProgress

    switch position {
    case .center:
      // Center the text within the callout
      let textWidth = text.size(with: labelStyle).width
      let totalContentWidth = (cachedIcon != nil ? 20 + iconTextGap : 0) + textWidth
      let contentStartX = baseCenter.x - totalContentWidth * 0.5
      let textX = contentStartX + (cachedIcon != nil ? 20 + iconTextGap : 0)
      labelPoint = Point(textX, lineTopY)
    case .topLeft:
      // Use the existing left-aligned positioning
      labelPoint = Point(contentX, lineTopY)
    }

    text.draw(at: labelPoint, style: labelStyle, context: context)
  }

  /// Convenience method to draw the callout at a logical position with a default size.
  /// - Parameters:
  ///   - position: The logical position for the callout.
  ///   - size: The size of the callout area; defaults to `Size(520, 44)`.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  @MainActor public mutating func draw(
    at position: CalloutPosition,
    size: Size = Size(Float(WIDTH) / 3, 36),
    context: GraphicsContext? = nil
  ) {
    self.position = position
    let viewportH = Float(HEIGHT)
    let origin: Point = {
      switch position {
      case .topLeft:
        return Point(0, viewportH)
      case .center:
        return Point(Float(WIDTH) * 0.5, viewportH * 0.5)
      }
    }()
    let rect = Rect(origin: origin, size: size)
    draw(in: rect, context: context)
  }

  private func iconResourcePath(_ icon: CalloutIcon) -> String? {
    switch icon {
    case .chevron: return "UI/Icons/callouts/chevron.png"
    case .info: return "UI/Icons/callouts/info.png"
    case .location: return "UI/Icons/callouts/location.png"
    }
  }
}
