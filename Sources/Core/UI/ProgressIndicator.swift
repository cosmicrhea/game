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
    draw(centeredAt: center)
  }

  func draw(centeredAt center: Point) {
    let targetSize = size != nil ? Size(size!, size!) : image.naturalSize
    let origin = Point(center.x - targetSize.width / 2, center.y - targetSize.height / 2)
    let rect = Rect(origin: origin, size: targetSize)
    image.draw(in: rect, rotation: angle, tint: tint)
  }

  func draw(in rect: Rect) {
    let targetSize: Size
    if let fixedSize = size {
      let edge = min(fixedSize, min(rect.size.width, rect.size.height))
      targetSize = Size(edge, edge)
    } else {
      let natural = image.naturalSize
      let scale = min(rect.size.width / natural.width, rect.size.height / natural.height)
      targetSize = Size(natural.width * scale, natural.height * scale)
    }

    let origin = Point(rect.midX - targetSize.width / 2, rect.midY - targetSize.height / 2)
    let drawRect = Rect(origin: origin, size: targetSize)
    image.draw(in: drawRect, rotation: angle, tint: tint)
  }
}
