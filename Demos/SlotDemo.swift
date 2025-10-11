import Foundation
import GL
import GLFW
import GLMath

/// Demo for testing the slot shader with textured border
@MainActor
final class SlotDemo: RenderLoop {
  private let inputPrompts = InputPrompts()
  private var slotEffect = GLScreenEffect("Common/Slot")
  private var panelSize = Size(80, 80)
  private var panelCenter = Point(400, 300)
  private var borderThickness: Float = 8.0
  private var cornerRadius: Float = 12.0
  private var noiseScale: Float = 0.02
  private var noiseStrength: Float = 0.3

  // Colors
  private var panelColor = Color(0.1, 0.1, 0.1)
  private var borderColor = Color(0.4, 0.4, 0.4)
  private var borderHighlight = Color(0.6, 0.6, 0.6)
  private var borderShadow = Color(0.2, 0.2, 0.2)

  init() {
    // GLScreenEffect handles shader loading automatically
  }

  func update(deltaTime: Float) {
    // Animate noise for subtle texture movement
    let time = Float(Date().timeIntervalSince1970)
    noiseScale += sin(time * 0.5) * 0.001
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .w:
      panelSize.height += 10
    case .s:
      panelSize.height -= 10
    case .a:
      panelSize.width -= 10
    case .d:
      panelSize.width += 10
    case .up:
      panelCenter.y -= 10
    case .down:
      panelCenter.y += 10
    case .left:
      panelCenter.x -= 10
    case .right:
      panelCenter.x += 10
    case .equal:
      borderThickness += 1
    case .minus:
      borderThickness = max(1, borderThickness - 1)
    case .r:
      // Reset to defaults
      panelSize = Size(80, 80)
      panelCenter = Point(400, 300)
      borderThickness = 8.0
      cornerRadius = 12.0
      noiseScale = 0.02
      noiseStrength = 0.3
    case .escape:
      break
    default:
      break
    }
  }

  func draw() {
    // Dark background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the slot using GLScreenEffect
    slotEffect.draw { shader in
      // Set uniforms
      shader.setVec2("uPanelSize", value: (panelSize.width, panelSize.height))
      shader.setVec2("uPanelCenter", value: (panelCenter.x, panelCenter.y))
      shader.setFloat("uBorderThickness", value: borderThickness)
      shader.setFloat("uCornerRadius", value: cornerRadius)
      shader.setFloat("uNoiseScale", value: noiseScale)
      shader.setFloat("uNoiseStrength", value: noiseStrength)

      // Set colors
      shader.setVec3("uPanelColor", value: (x: panelColor.red, y: panelColor.green, z: panelColor.blue))
      shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
      shader.setVec3(
        "uBorderHighlight", value: (x: borderHighlight.red, y: borderHighlight.green, z: borderHighlight.blue))
      shader.setVec3("uBorderShadow", value: (x: borderShadow.red, y: borderShadow.green, z: borderShadow.blue))
    }

    // Draw instructions
    let instructions = [
      "WASD: Resize slot",
      "Arrow Keys: Move slot",
      "+/-: Border thickness",
      "R: Reset to defaults",
      "ESC: Exit",
    ]

    for (index, instruction) in instructions.enumerated() {
      instruction.draw(
        at: Point(20, Float(HEIGHT) - 20 - Float(index * 25)),
        style: TextStyle(fontName: "Determination", fontSize: 18, color: .white),
        anchor: .topLeft
      )
    }

    // Draw slot info
    let info = [
      "Slot Size: \(Int(panelSize.width))x\(Int(panelSize.height))",
      "Border Thickness: \(Int(borderThickness))",
      "Corner Radius: \(Int(cornerRadius))",
      "Noise Scale: \(String(format: "%.3f", noiseScale))",
    ]

    for (index, line) in info.enumerated() {
      line.draw(
        at: Point(Float(WIDTH) - 20, Float(HEIGHT) - 20 - Float(index * 20)),
        style: TextStyle(fontName: "Determination", fontSize: 16, color: .white),
        anchor: .topLeft
      )
    }
  }

}
