@MainActor
final class FocusRing {
  private let effect = GLScreenEffect("Common/FocusRing")

  var cornerRadius: Float = 8
  var ringThickness: Float = 3
  var glowThickness: Float = 2
  var baseAlpha: Float = 0.55
  var glowAlpha: Float = 0.35
  var pulseStrength: Float = 0.18
  var noiseStrength: Float = 0.2
  var padding: Float = 0
  let isInterior: Bool

  private var ringColor: Color = Color(0.7, 0.75, 0.85, 1.0)  // zinc/very-bright-blue
  private var glowColor: Color = Color(0.75, 0.8, 0.9, 0.6)   // lighter zinc/blue glow

  init(isInterior: Bool = true) {
    self.isInterior = isInterior
  }

  func draw(around rect: Rect, intensity: Float = 1.0, padding customPadding: Float? = nil) {
    guard intensity > 0.001 else { return }

    let inset = customPadding ?? padding
    let expandedRect = Rect(
      x: rect.origin.x - inset,
      y: rect.origin.y - inset,
      width: rect.size.width + inset * 2,
      height: rect.size.height + inset * 2
    )

    effect.draw { program in
      program.setVec2("uRectCenter", value: (expandedRect.midX, expandedRect.midY))
      program.setVec2("uRectSize", value: (expandedRect.size.width, expandedRect.size.height))
      program.setFloat("uCornerRadius", value: cornerRadius + inset * 0.5)
      program.setFloat("uRingThickness", value: ringThickness)
      program.setFloat("uGlowThickness", value: glowThickness)
      program.setFloat("uRingAlpha", value: baseAlpha * intensity)
      program.setFloat("uGlowAlpha", value: glowAlpha * intensity)
      program.setVec3("uRingColor", value: (ringColor.red, ringColor.green, ringColor.blue))
      program.setVec3("uGlowColor", value: (glowColor.red, glowColor.green, glowColor.blue))
      program.setFloat("uPulseStrength", value: pulseStrength * intensity)
      program.setFloat("uNoiseStrength", value: noiseStrength)
      program.setFloat("uIsInterior", value: isInterior ? 1.0 : 0.0)
    }
  }

  func draw(around rect: Rect, intensity: Float = 1.0, paddingX: Float, paddingY: Float) {
    guard intensity > 0.001 else { return }

    let expandedRect = Rect(
      x: rect.origin.x - paddingX,
      y: rect.origin.y - paddingY,
      width: rect.size.width + paddingX * 2,
      height: rect.size.height + paddingY * 2
    )

    effect.draw { program in
      program.setVec2("uRectCenter", value: (expandedRect.midX, expandedRect.midY))
      program.setVec2("uRectSize", value: (expandedRect.size.width, expandedRect.size.height))
      program.setFloat("uCornerRadius", value: cornerRadius + (paddingX + paddingY) * 0.25)
      program.setFloat("uRingThickness", value: ringThickness)
      program.setFloat("uGlowThickness", value: glowThickness)
      program.setFloat("uRingAlpha", value: baseAlpha * intensity)
      program.setFloat("uGlowAlpha", value: glowAlpha * intensity)
      program.setVec3("uRingColor", value: (ringColor.red, ringColor.green, ringColor.blue))
      program.setVec3("uGlowColor", value: (glowColor.red, glowColor.green, glowColor.blue))
      program.setFloat("uPulseStrength", value: pulseStrength * intensity)
      program.setFloat("uNoiseStrength", value: noiseStrength)
      program.setFloat("uIsInterior", value: isInterior ? 1.0 : 0.0)
    }
  }
}
