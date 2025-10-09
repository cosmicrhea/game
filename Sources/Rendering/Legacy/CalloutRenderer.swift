import Foundation
import GL
import GLFW

/// Renders a translucent callout box using the `effects/callout` shader and can
/// optionally draw an icon and a single-line label inside.
final class CalloutRenderer {
  enum Anchor {
    case topLeft
    case bottomLeft
    case center
  }

  enum Fade {
    case none
    case left
    case right
    case both
  }

  // Animation state
  private var isVisible: Bool = true
  private var targetVisible: Bool = true
  private var animationProgress: Float = 0.0
  private var animationVelocity: Float = 0.0
  private var lastUpdateTime: Double = 0.0

  // Spring animation parameters
  private let springStiffness: Float = 2.5
  private let springDamping: Float = 0.8
  private let animationSpeed: Float = 7.0

  // Immutable configuration
  private let effect = GLScreenEffect("effects/callout")
  private let defaultLabelRenderer: TextRenderer

  init(labelFontName: String = "Dream Orphans Bd", labelSize: Float = 24) {
    self.defaultLabelRenderer = TextRenderer(labelFontName, labelSize)!
    self.lastUpdateTime = GLFWSession.currentTime
  }

  /// Determines the appropriate icon size based on the icon name
  private func iconSize(for iconName: String) -> (w: Float, h: Float) {
    switch iconName {
    //    case "bubble-right", "curved-right", "swoosh-right":
    case "curved-right":
      return (32, 32)
    default:
      return (24, 24)
    }
  }

  /// Update animation state. Call this every frame.
  @MainActor func update(deltaTime: Float) {
    let currentTime = GLFWSession.currentTime
    let dt = Float(currentTime - lastUpdateTime)
    lastUpdateTime = currentTime

    // Update target visibility
    if targetVisible != isVisible {
      isVisible = targetVisible
    }

    // Spring animation for progress
    let targetProgress: Float = isVisible ? 1.0 : 0.0
    let springForce = (targetProgress - animationProgress) * springStiffness
    let dampingForce = -animationVelocity * springDamping
    let acceleration = springForce + dampingForce

    animationVelocity += acceleration * dt * animationSpeed
    animationProgress += animationVelocity * dt * animationSpeed

    // Clamp progress to [0, 1]
    animationProgress = max(0.0, min(1.0, animationProgress))

    // Stop animation when close to target
    if abs(targetProgress - animationProgress) < 0.001 && abs(animationVelocity) < 0.001 {
      animationProgress = targetProgress
      animationVelocity = 0.0
    }
  }

  /// Set the visibility of the callout with animation
  func setVisible(_ visible: Bool) {
    targetVisible = visible
  }

  /// Draw the callout and its optional contents.
  @MainActor func draw(
    windowSize: (w: Int32, h: Int32),

    // Geometry
    size: (w: Float, h: Float) = (520, 44),
    position: (x: Float, y: Float) = (24, 24),
    anchor: Anchor = .topLeft,

    // Visuals
    fade: Fade = .right,
    fadeWidthRatio: Float = 1.0 / 3.0,

    // Content
    icon: ImageRenderer? = nil,
    iconName: String? = nil,
    iconPaddingX: Float = 12,
    iconTextGap: Float = 8,
    iconColor: (Float, Float, Float, Float) = (0.6, 0.6, 0.6, 1),

    label: String? = nil,
    labelRenderer: TextRenderer? = nil,
    labelColor: (Float, Float, Float, Float) = (0.9, 0.9, 0.9, 1),

    // Animation
    visible: Bool = true
  ) {
    // Update target visibility
    setVisible(visible)

    // Early return if not visible and animation is complete
    if !visible && animationProgress <= 0.0 {
      return
    }

    // Compute callout center from anchor and position
    let px = position.x
    let py = position.y
    let w = size.w
    let h = size.h

    let baseCenter: (x: Float, y: Float) = {
      switch anchor {
      case .topLeft:
        return (px + w * 0.5, py - h * 0.5)
      case .bottomLeft:
        return (px + w * 0.5, py + h * 0.5)
      case .center:
        return (px, py)
      }
    }()

    // Apply animation: only the callout background fades, content slides
//    let center = baseCenter  // Background callout stays in place

    // Configure fades
    let fadeWidth = max(0, fadeWidthRatio) * w
    let leftWidth: Float = (fade == .left || fade == .both) ? fadeWidth : 0
    let rightWidth: Float = (fade == .right || fade == .both) ? fadeWidth : 0

    // UI should render on top: no depth/cull interference
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(false)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    // Ensure filled polys even if the app toggled wireframe
    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    // Draw the background callout (use original center, no translation)
    effect.draw { program in
      program.setVec2("uRectSize", value: (w, h))
      program.setVec2("uRectCenter", value: (baseCenter.x, baseCenter.y))
      if leftWidth > 0 { program.setFloat("uLeftFadeWidth", value: leftWidth) }
      if rightWidth > 0 { program.setFloat("uRightFadeWidth", value: rightWidth) }
      // Pass animation alpha to shader
      program.setFloat("uAnimationAlpha", value: animationProgress)
    }

    // Content layout with slide animation (left-aligned inside the box)
    let left = baseCenter.x - w * 0.5
    let slideDistance: Float = w * 0.1  // Slide distance for content
    let animatedContentX = left + iconPaddingX - slideDistance * (1.0 - animationProgress)

    var contentX = animatedContentX

    // Draw icon if provided
    if let icon = icon {
      let iconSize = iconName.map { self.iconSize(for: $0) } ?? (w: 24, h: 24)
      let iconY = baseCenter.y - iconSize.h * 0.5
      let animatedIconColor = (iconColor.0, iconColor.1, iconColor.2, iconColor.3 * animationProgress)
      icon.drawScaled(x: contentX, y: iconY, windowSize: windowSize, targetSize: iconSize, color: animatedIconColor)
      //      contentX += iconSize.w + iconTextGap
      contentX += 24 + iconTextGap  // FIXME
    }

    // Draw label if present
    if let text = label {
      let renderer = labelRenderer ?? defaultLabelRenderer
      let lineTopY = baseCenter.y + renderer.scaledLineHeight * 0.5
      let animatedLabelColor = (labelColor.0, labelColor.1, labelColor.2, labelColor.3 * animationProgress)
      renderer.draw(
        text,
        at: (contentX, lineTopY),
        windowSize: windowSize,
        color: animatedLabelColor,
        anchor: .topLeft
      )
    }

    // Restore GL state
    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(true)
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
  }
}
