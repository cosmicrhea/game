import struct Foundation.Date

@MainActor
final class TextInsertionIndicator {
  // Visuals
  var width: Float = 2
  var color: Color = .gray300
  var glowColor: Color = Color.white.withAlphaComponent(0.18)

  // Animation
  var pulseSpeed: Float = 1.6  // cycles per second
  var minAlpha: Float = 0.55
  var maxAlpha: Float = 1.0
  var typingHoldDuration: Float = 0.16
  var yOffset: Float = 0

  // State
  private var lastTime: Double = Date().timeIntervalSinceReferenceDate
  private var phase: Float = 0
  private var typingHold: Float = 0

  func pingTyping() { typingHold = typingHoldDuration }

  func draw(at x: Float, y: Float, height: Float, focused: Bool) {
    let now = Date().timeIntervalSinceReferenceDate
    let dt = Float(now - lastTime)
    lastTime = now
    phase = (phase + dt * pulseSpeed).truncatingRemainder(dividingBy: 1.0)
    typingHold = max(0, typingHold - dt)

    // Compute alpha: solid while typing, otherwise a subtle pulse
    let alpha: Float
    if typingHold > 0 || !focused {
      alpha = maxAlpha
    } else {
      let t = 0.5 + 0.5 * sin(phase * .pi * 2)
      alpha = minAlpha + (maxAlpha - minAlpha) * t
    }

    // Glow backdrop (slightly wider than caret)
    let glowW = max(width + 4, 6)
    let gx = x - (glowW - width) * 0.5
    Rect(x: gx, y: y + yOffset, width: glowW, height: height).fill(with: glowColor)

    // Caret body
    Rect(x: x, y: y + yOffset, width: width, height: height).fill(with: color.withAlphaComponent(alpha))
  }
}
