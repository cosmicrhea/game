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

  // Geometry
  var size: (w: Float, h: Float) = (520, 44)
  var position: (x: Float, y: Float) = (24, 24)  // Interpreted by `anchor`
  var anchor: Anchor = .topLeft

  // Visuals
  var fade: Fade = .right
  /// Fade width as a fraction of the callout width (e.g. 0.33 for one-third)
  var fadeWidthRatio: Float = 1.0 / 3.0

  // Content
  var icon: ImageRenderer?
  var iconSize: (w: Float, h: Float) = (24, 24)
  var iconPaddingX: Float = 12
  var iconTextGap: Float = 2
  var label: String?
  var labelRenderer: TextRenderer? = TextRenderer("Dream Orphans Bd", 24)
  var labelColor: (Float, Float, Float, Float) = (1, 1, 1, 1)

  // Internals
  private let effect = ScreenEffect("effects/callout")

  init() {}

  /// Draw the callout and its optional contents.
  @MainActor func draw(windowSize: (w: Int32, h: Int32)) {
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
    //    let top = center.y + h * 0.5

    var contentX = left + iconPaddingX

    // Draw icon if provided
    if let icon = icon {
      let iconY = center.y - iconSize.h * 0.5
      icon.drawScaled(x: contentX, y: iconY, windowSize: windowSize, targetSize: iconSize)
      contentX += iconSize.w + iconTextGap
    }

    // Draw label if present
    if let text = label, let renderer = labelRenderer {
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
