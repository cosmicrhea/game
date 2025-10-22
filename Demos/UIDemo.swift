@MainActor
final class UIDemo: RenderLoop {
  private let indicator = ProgressIndicator()

  init() {}

  func update(deltaTime: Float) {
    indicator.update(deltaTime: deltaTime)
  }

  func draw() {
    // UI background
    GraphicsContext.current?.renderer.setClearColor(Color(0.08, 0.08, 0.1, 1))

    // Title text
    let titleStyle = TextStyle(fontName: "Determination", fontSize: 28, color: .white)
    "UI Demo — Progress Indicator".draw(
      at: Point(20, 20),
      style: titleStyle,
      anchor: .topLeft
    )

    // Spinner
    indicator.draw()

    // Hint
    let hintStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray300)
    "Spinning circle shows center-aligned UI indicator".draw(
      at: Point(20, 54),
      style: hintStyle,
      anchor: .topLeft
    )
  }
}
