import Foundation
import GL

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

  // Immutable configuration
  private let effect = ScreenEffect("effects/callout")
  private let defaultLabelRenderer: TextRenderer

  init(labelFontName: String = "Dream Orphans Bd", labelSize: Float = 24) {
    self.defaultLabelRenderer = TextRenderer(labelFontName, labelSize)!
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
    labelColor: (Float, Float, Float, Float) = (0.9, 0.9, 0.9, 1)
  ) {
    // Compute callout center from anchor and position
    let px = position.x
    let py = position.y
    let w = size.w
    let h = size.h

    let center: (x: Float, y: Float) = {
      switch anchor {
      case .topLeft:
        return (px + w * 0.5, py - h * 0.5)
      case .bottomLeft:
        return (px + w * 0.5, py + h * 0.5)
      case .center:
        return (px, py)
      }
    }()

    // Configure fades
    let fadeWidth = max(0, fadeWidthRatio) * w
    let leftWidth: Float = (fade == .left || fade == .both) ? fadeWidth : 0
    let rightWidth: Float = (fade == .right || fade == .both) ? fadeWidth : 0

    // UI should render on top: no depth/cull interference
    let depthWasEnabled = glIsEnabled(GL_DEPTH_TEST) == GLboolean(GL_TRUE)
    let cullWasEnabled = glIsEnabled(GL_CULL_FACE) == GLboolean(GL_TRUE)
    glDisable(GL_DEPTH_TEST)
    glDisable(GL_CULL_FACE)
    glDepthMask(GLboolean(GL_FALSE))
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    // Ensure filled polys even if the app toggled wireframe
    var prevPoly: [GLint] = [0, 0]
    prevPoly.withUnsafeMutableBufferPointer { buf in
      glGetIntegerv(GL_POLYGON_MODE, buf.baseAddress)
    }
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

    // Draw the background callout
    effect.draw { program in
      program.setVec2("uRectSize", value: (w, h))
      program.setVec2("uRectCenter", value: (center.x, center.y))
      if leftWidth > 0 { program.setFloat("uLeftFadeWidth", value: leftWidth) }
      if rightWidth > 0 { program.setFloat("uRightFadeWidth", value: rightWidth) }
    }

    // Content layout (left-aligned inside the box)
    let left = center.x - w * 0.5

    var contentX = left + iconPaddingX

    // Draw icon if provided
    if let icon = icon {
      let iconSize = iconName.map { self.iconSize(for: $0) } ?? (w: 24, h: 24)
      let iconY = center.y - iconSize.h * 0.5
      icon.drawScaled(x: contentX, y: iconY, windowSize: windowSize, targetSize: iconSize, color: iconColor)
      //      contentX += iconSize.w + iconTextGap
      contentX += 24 + iconTextGap  // FIXME
    }

    // Draw label if present
    if let text = label {
      let renderer = labelRenderer ?? defaultLabelRenderer
      let lineTopY = center.y + renderer.scaledLineHeight * 0.5
      renderer.draw(
        text,
        at: (contentX, lineTopY),
        windowSize: windowSize,
        color: labelColor,
        anchor: .topLeft
      )
    }

    // Restore GL state
    glPolygonMode(GL_FRONT_AND_BACK, GLenum(prevPoly[0]))
    glDepthMask(GLboolean(GL_TRUE))
    if depthWasEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if cullWasEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
  }
}
