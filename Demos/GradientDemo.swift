/// Demo showcasing the Gradient drawing system
public final class GradientDemo: RenderLoop {
  private var time: Float = 0

  public init() {}

  public func update(window: Window, deltaTime: Float) {
    time += deltaTime
  }

  public func draw() {
    guard let context = GraphicsContext.current else { return }

    // Set a dark background
    context.renderer.setClearColor(.gray700)

    // Create some example gradients
    let blackToWhite = Gradient(startingColor: .black, endingColor: .white)
    let rainbow = Gradient.rainbow
    let customGradient = Gradient(colors: [.red, .green, .blue], locations: [0.0, 0.5, 1.0])
    let blackToClear = Gradient(startingColor: .black, endingColor: .clear)
    let animatedGradient = Gradient(
      colors: [
        .red, .orange, .yellow, .green, .blue, .purple,
      ], locations: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])

    // Draw linear gradients
    let rect1 = Rect(x: 50, y: 50, width: 200, height: 100)
    context.drawLinearGradient(blackToWhite, in: rect1, angle: 0)

    let rect2 = Rect(x: 300, y: 50, width: 200, height: 100)
    context.drawLinearGradient(rainbow, in: rect2, angle: 45)

    let rect3 = Rect(x: 550, y: 50, width: 200, height: 100)
    context.drawLinearGradient(customGradient, in: rect3, angle: 90)

    // Draw radial gradients
    let rect4 = Rect(x: 50, y: 200, width: 200, height: 100)
    context.drawRadialGradient(blackToWhite, in: rect4, center: Point(0.5, 0.5))

    let rect5 = Rect(x: 300, y: 200, width: 200, height: 100)
    context.drawRadialGradient(rainbow, in: rect5, center: Point(0.3, 0.7))

    let rect6 = Rect(x: 550, y: 200, width: 200, height: 100)
    context.drawRadialGradient(customGradient, in: rect6, center: Point(0.8, 0.2))

    // Animated gradient
    let animatedRect = Rect(x: 50, y: 350, width: 300, height: 100)
    let animatedAngle = time * 30  // Rotate 30 degrees per second
    context.drawLinearGradient(animatedGradient, in: animatedRect, angle: animatedAngle)

    // Black to clear gradient (alpha fade)
    let fadeRect = Rect(x: 400, y: 350, width: 200, height: 100)
    context.drawLinearGradient(blackToClear, in: fadeRect, angle: 0)

    // Black to clear radial gradient
    let fadeRadialRect = Rect(x: 650, y: 350, width: 200, height: 100)
    context.drawRadialGradient(blackToClear, in: fadeRadialRect, center: Point(0.5, 0.5))

    // Draw labels
    "Linear Gradients".draw(
      at: Point(50, 30),
      style: .itemName
    )

    "Radial Gradients".draw(
      at: Point(50, 180),
      style: .itemName
    )

    "Animated Gradient".draw(
      at: Point(50, 330),
      style: .itemName
    )

    "Alpha Fade".draw(
      at: Point(400, 330),
      style: .itemName
    )
  }
}
