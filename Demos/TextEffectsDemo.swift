import GL
import GLFW
import GLMath
import STBRectPack

@MainActor
final class TextEffectsDemo: RenderLoop {
  private let titleStyle = TextStyle(fontName: "Creato Display Bold", fontSize: 16, color: .white)
  private let sampleText = "The quick brown fox jumps over the lazy dog"

  private let effects: [(name: String, style: TextStyle)] = {
    let sampleText = "The quick brown fox jumps over the lazy dog"

    return [
      (
        "Plain Text",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left
        )
      ),
      (
        "Red Outline",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left,
          strokeWidth: 2.0,
          strokeColor: Color(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        )
      ),
      (
        "Document View",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 0.745, green: 0.749, blue: 0.655, alpha: 1.0),
          alignment: .left,
          strokeWidth: 2.0,
          strokeColor: Color(red: 0.078, green: 0.059, blue: 0.055, alpha: 1.0)
        )
      ),
      (
        "Black Shadow",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left,
          shadowWidth: 3.0,
          shadowOffset: Point(3, -3),
          shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.7)
        )
      ),
      (
        "Green Outline + Shadow",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left,
          strokeWidth: 1.5,
          strokeColor: Color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),
          shadowWidth: 2.0,
          shadowOffset: Point(2, -2),
          shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.5)
        )
      ),
      (
        "Thick Blue Outline",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left,
          strokeWidth: 4.0,
          strokeColor: Color(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        )
      ),
      (
        "Soft Purple Shadow",
        TextStyle(
          fontName: "Creato Display Medium",
          fontSize: 24,
          color: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
          alignment: .left,
          shadowWidth: 4.0,
          shadowOffset: Point(3, -3),
          shadowColor: Color(red: 0.5, green: 0.0, blue: 0.5, alpha: 0.4)
        )
      ),
    ]
  }()

  func draw() {
    guard let context = GraphicsContext.current else { return }

    // Clear screen
    glClearColor(0.1, 0.1, 0.2, 1.0)
    glClear(GL_COLOR_BUFFER_BIT)

    let ws = (Int32(WIDTH), Int32(HEIGHT))

    // Layout constants
    let titleHeight: Float = 24
    let textHeight: Float = 32
    let padding: Float = 16
    let marginX: Float = 40
    let marginY: Float = 40
    let spacingX: Float = 40
    let spacingY: Float = 60

    // Measure each effect
    var effectData: [(name: String, style: TextStyle, width: Float, height: Float)] = []

    for effect in effects {
      let textSize = sampleText.size(with: effect.style)
      let totalWidth = max(textSize.width, Float(effect.name.count) * 8)  // Rough title width
      let totalHeight = titleHeight + textHeight + padding
      effectData.append(
        (name: effect.name, style: effect.style, width: totalWidth, height: totalHeight))
    }

    // Pack rectangles using STBRectPack
    let binWidth = WIDTH - Int(marginX * 2)
    let binHeight = HEIGHT - Int(marginY * 2)

    let rectSizes = effectData.map { (width: Int($0.width + spacingX), height: Int($0.height + spacingY)) }

    let (packedRects, _) = RectPacking.pack(
      binWidth: binWidth,
      binHeight: binHeight,
      sizes: rectSizes,
      heuristic: .skylineBL
    )

    // Draw each effect at its packed position
    for (index, effect) in effectData.enumerated() {
      guard index < packedRects.count else { continue }
      let packed = packedRects[index]
      guard packed.wasPacked else { continue }

      // Convert packed coordinates to screen coordinates (top-left aligned)
      let screenX = marginX + Float(packed.x)
      let screenY = marginY + Float(packed.y)

      // Draw title
      let titleColor = Color(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
      let titleStyleWithColor = TextStyle(
        fontName: titleStyle.fontName,
        fontSize: titleStyle.fontSize,
        color: titleColor
      )

      effect.name.draw(
        at: Point(screenX, screenY),
        style: titleStyleWithColor,
        anchor: .topLeft,
        context: context
      )

      // Draw the text effect
      sampleText.draw(
        at: Point(screenX, screenY + titleHeight + 8),
        style: effect.style,
        anchor: .topLeft,
        context: context
      )

      // Draw debug rectangle if needed
      if Config.current.wireframeMode {
        Debug.drawRect(
          x: screenX, y: screenY, width: effect.width, height: effect.height,
          windowSize: ws, lineWidth: 1.0
        )
      }
    }
  }
}
