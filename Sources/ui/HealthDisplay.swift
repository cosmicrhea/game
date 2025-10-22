import enum GLFW.GLFWSession
import struct GLFW.Keyboard

@MainActor
final class HealthDisplay {
  private let effect = GLScreenEffect("UI/HealthDisplay")

  // State
  var health: Float = 1.0 { didSet { health = max(0.0, min(1.0, health)) } }

  // Layout rect (pixels)
  private var rect: Rect {
    let w: Float = 128 + 25
    let h: Float = 128
    let origin = Point(0, 96)
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
      program.setFloat("uThickness", value: 3.0)
      program.setFloat("uBgDim", value: 0.2)
      program.setFloat("uBgAlpha", value: 0.85)
      program.setFloat("uSpikeAmp", value: 0.9)
      program.setFloat("uSpikeFreq", value: 140.0)
      program.setFloat("uSpikeThreshold", value: 0.76)
      program.setFloat("uGlow", value: 0.35)
      program.setFloat("uDangerArc", value: 0.22)

      // Provide expected uniforms for shader
      program.setFloat("health", value: health)
    }
  }
}
