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
    Rect(x: 50, y: 50, width: 200, height: 100).fill(with: blackToWhite)
    Rect(x: 300, y: 50, width: 200, height: 100).fill(with: rainbow, angle: 45)
    Rect(x: 550, y: 50, width: 200, height: 100).fill(with: customGradient, angle: 90)

    // Draw radial gradients
    Rect(x: 50, y: 200, width: 200, height: 100).fill(with: blackToWhite, center: Point(0.5, 0.5))
    Rect(x: 300, y: 200, width: 200, height: 100).fill(with: rainbow, center: Point(0.3, 0.7))
    Rect(x: 550, y: 200, width: 200, height: 100).fill(with: customGradient, center: Point(0.8, 0.2))

    // Animated gradient
    let animatedAngle = time * 30  // Rotate 30 degrees per second
    Rect(x: 50, y: 350, width: 300, height: 100).fill(with: animatedGradient, angle: animatedAngle)

    // Black to clear gradient (alpha fade)
    Rect(x: 400, y: 350, width: 200, height: 100).fill(with: blackToClear)

    // Black to clear radial gradient
    Rect(x: 650, y: 350, width: 200, height: 100).fill(with: blackToClear, center: Point(0.5, 0.5))

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
