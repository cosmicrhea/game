final class HealthDisplay {
  private let circleEffect = GLScreenEffect("UI/HealthDisplay")

  var health: Float = 1.0 { didSet { health = max(0.0, min(1.0, health)) } }

  var rect: Rect {
    let w: Float = 128
    let h: Float = 128
    let origin = Point(44, 96 + 24)
    return Rect(origin: origin, size: Size(w, h))
  }

  @MainActor func draw() {
    let r = rect
    let center = (r.origin.x + r.size.width * 0.5, r.origin.y + r.size.height * 0.5)

    circleEffect.draw { program in
      program.setVec2("uRectCenter", value: (center.0, center.1))
      program.setVec2("uRectSize", value: (r.size.width, r.size.height))
      program.setFloat("uThickness", value: 4.5)
      program.setFloat("uBgDim", value: 0.6)
      program.setFloat("uBgAlpha", value: 0.85)

      program.setFloat("uSpikeAmp", value: 1.1)
      program.setFloat("uSpikeFreq", value: 120.0)
      program.setFloat("uSpikeThreshold", value: 0.72)
      program.setFloat("uGlow", value: 0.55)
      program.setFloat("uDangerArc", value: 0.24)
      program.setFloat("uRadius", value: 0.72)
      program.setFloat("uSpikeLen", value: 0.20)
      program.setFloat("uGlowRadius", value: 0.14)
      program.setFloat("uInnerAlpha", value: 0.4)

      program.setFloat("health", value: health)
    }

    // Status text
    let status: (text: String, color: Color) = {
      switch health {
      case let h where h >= 0.50: return ("Nominal", Color(0.65, 0.88, 0.95, 1.0))  // OK? Fine? Clear? Nominal?
      case let h where h >= 0.33: return ("Warning", Color.amber) // Warning? Caution?
      default: return ("Critical", Color.rose)
      }
    }()

    let style = TextStyle(
      fontName: "CreatoDisplay-Bold",
      fontSize: 20,
      color: status.color,
      alignment: .center,
      strokeWidth: 1,
      strokeColor: .black,
    )

    let textX = r.origin.x + r.size.width * 0.5
    let textY = r.origin.y - 16
    status.text.draw(at: Point(textX, textY), style: style, anchor: .bottom)
  }
}
