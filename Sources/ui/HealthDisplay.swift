import enum GLFW.GLFWSession
import struct GLFW.Keyboard

@MainActor
final class HealthDisplay {
  private let ecgEffect = GLScreenEffect("UI/HealthECG")

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
    // 16:9-ish: make it wider than tall
    var r = rect
    r.size.width = max(r.size.width, r.size.height * (16.0 / 9.0))
    r.origin.x = r.origin.x - 8  // shift left slightly to keep visual balance
    let center = (r.origin.x + r.size.width * 0.5, r.origin.y + r.size.height * 0.5)

    // Draw ECG rectangle
    ecgEffect.draw { program in
      program.setVec2("uRectCenter", value: (center.0, center.1))
      program.setVec2("uRectSize", value: (r.size.width, r.size.height))
      program.setFloat("uGridAlpha", value: 0.35)
      program.setFloat("uGlow", value: 0.85)
      program.setFloat("uLineWidth", value: 2.0)
      // Frosted panel
      program.setFloat("uBgDim", value: 0.55)
      program.setFloat("uBgAlpha", value: 0.85)
      program.setFloat("uCorner", value: 10.0)
      program.setFloat("uEdgeSoftness", value: 2.0)
      program.setFloat("uBorderThickness", value: 1.5)
      program.setFloat("uBorderSoftness", value: 1.0)
      program.setVec3("uPanelTint", value: (x: 0.06, y: 0.10, z: 0.12))
      program.setVec3("uBorderColor", value: (x: 0.85, y: 0.90, z: 0.95))
      program.setFloat("uPanelInsetPx", value: 6.0)
      program.setFloat("uSpikeLenPx", value: 10.0)
      // Frost spikes
      let danger = max(0.0, 1.0 - health)
      program.setFloat("uFrostThickness", value: 6.0)
      program.setFloat("uGlowRadius", value: 4.0)
      program.setFloat("uSpikeAmp", value: 0.7 + danger * 0.4)
      program.setFloat("uSpikeFreq", value: 240.0)
      program.setFloat("uSpikeThreshold", value: 0.75 - danger * 0.1)

      program.setFloat("health", value: health)
    }

    // Status text
    let status: (text: String, color: Color) = {
      switch health {
      case let h where h >= 0.50: return ("OK", Color(0.65, 0.88, 0.95, 1.0))
      case let h where h >= 0.33: return ("Caution", Color(0.95, 0.72, 0.25, 1.0))
      default: return ("Fatal", Color(1.0, 0.25, 0.20, 1.0))
      }
    }()

    let style = TextStyle(
      fontName: "CreatoDisplay-Bold",
      fontSize: 18,
      color: status.color,
      alignment: .left,
      strokeWidth: 1,
      strokeColor: Color(0, 0, 0, 0),
    )

    let textOrigin = Point(r.origin.x + 6, r.origin.y + 12)
    status.text.draw(at: textOrigin, style: style, anchor: .bottomLeft)
  }
}
