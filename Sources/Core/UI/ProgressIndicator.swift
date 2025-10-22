// TODO:
public final class ProgressIndicator {
  let image = Image("UI/Icons/phosphor-icons/circle-notch.svg")
  private var angle: Float = 0
  public var speed: Float = 2.5  // radians per second
  public var size: Float? = 48
  public var tint: Color = .gray700

  func update(deltaTime: Float) {
    angle -= speed * deltaTime  // clockwise
    if angle > .pi * 2 { angle -= .pi * 2 }
    if angle < -.pi * 2 { angle += .pi * 2 }
  }

  func draw() {
    let center = Point(Engine.viewportSize.width / 2, Engine.viewportSize.height / 2)
    let drawSize = size != nil ? Size(size!, size!) : image.naturalSize
    let origin = Point(center.x - drawSize.width / 2, center.y - drawSize.height / 2)
    let rect = Rect(origin: origin, size: drawSize)
    image.draw(in: rect, rotation: angle, tint: tint)
  }
}
