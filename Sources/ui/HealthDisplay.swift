import enum GLFW.GLFWSession
import struct GLFW.Keyboard

@MainActor
final class HealthDisplay {
  private let effect = GLScreenEffect("UI/HealthDisplay")

  // State
  var health: Float = 1.0 { didSet { health = max(0.0, min(1.0, health)) } }

  // Layout rect (pixels)
  private var rect: Rect {
    let w: Float = 128
    let h: Float = 128
    let origin = Point(44, 96)
    return Rect(origin: origin, size: Size(w, h))
  }

  func update(deltaTime: Float) {}

  func onKeyPressed(_ key: Keyboard.Key) {
    if key == .num9 { health = min(1.0, health + 0.05) }
    if key == .num0 { health = max(0.0, health - 0.05) }
  }

  func draw() {
    let r = rect
    let center = (r.origin.x + r.size.width * 0.5, r.origin.y + r.size.height * 0.5)
    effect.draw { program in
      program.setVec2("uRectCenter", value: (center.0, center.1))
      program.setVec2("uRectSize", value: (r.size.width, r.size.height))
      program.setFloat("uThickness", value: 7.0)
      program.setFloat("uBgDim", value: 0.6)
      program.setFloat("uBgAlpha", value: 0.85)

      // Health-reactive tuning
      let danger = max(0.0, 1.0 - health)
      program.setFloat("uSpikeAmp", value: 0.6 + danger * 0.6)
      program.setFloat("uSpikeFreq", value: 110.0 + danger * 30.0)
      program.setFloat("uSpikeThreshold", value: 0.70 - danger * 0.15)
      program.setFloat("uGlow", value: 0.45 + danger * 0.25)
      program.setFloat("uDangerArc", value: 0.10 + danger * 0.30)

      program.setFloat("uRadius", value: 0.72)
      program.setFloat("uSpikeLen", value: 0.20)
      program.setFloat("uGlowRadius", value: 0.14)
      program.setFloat("uInnerAlpha", value: 0.4)

      // Provide expected uniforms for shader
      program.setFloat("health", value: health)
    }
  }
}
