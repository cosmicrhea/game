public final class ProgressIndicator {
  let image = Image("UI/Icons/phosphor-icons/circle-notch.svg")
  private var angle: Float = 0
  public var speed: Float = 2.5  // radians per second
  public var size: Float? = 48
  public var tint: Color = .gray700
  public var strokeWidth: Float? = nil
  public var strokeColor: Color? = nil
  
  // Fade animation
  private var opacity: Float = 0.0
  private var targetOpacity: Float = 0.0
  private let fadeDuration: Float = 0.15  // 150ms
  
  // Minimum visibility tracking
  private var visibleStartTime: Float? = nil
  private let minimumVisibleDuration: Float = 0.5  // Half rotation (~0.5s at speed 2.5)
  
  // Public visibility control
  public var isVisible: Bool {
    get { targetOpacity > 0 }
    set {
      if newValue && targetOpacity == 0 {
        // Starting to show - record start time
        visibleStartTime = 0.0
      }
      targetOpacity = newValue ? 1.0 : 0.0
    }
  }
  
  public init() {}

  func update(deltaTime: Float) {
    // Update rotation
    angle -= speed * deltaTime  // clockwise
    if angle > .pi * 2 { angle -= .pi * 2 }
    if angle < -.pi * 2 { angle += .pi * 2 }
    
    // Update visibility timer
    if let startTime = visibleStartTime {
      visibleStartTime = startTime + deltaTime
    }
    
    // Handle fade animation with minimum visibility duration
    if targetOpacity > opacity {
      // Fading in - always allow
      opacity = min(opacity + deltaTime / fadeDuration, targetOpacity)
    } else if targetOpacity < opacity {
      // Fading out - check minimum duration
      if let startTime = visibleStartTime, startTime < minimumVisibleDuration {
        // Not visible long enough yet - stay at full opacity
        opacity = 1.0
      } else {
        // Can fade out now
        opacity = max(opacity - deltaTime / fadeDuration, targetOpacity)
        if opacity == 0 {
          visibleStartTime = nil
        }
      }
    }
  }

  func draw() {
    guard opacity > 0 else { return }
    let center = Point(Engine.viewportSize.width / 2, Engine.viewportSize.height / 2)
    draw(centeredAt: center)
  }

  func draw(centeredAt center: Point) {
    guard opacity > 0 else { return }
    let targetSize = size != nil ? Size(size!, size!) : image.naturalSize
    let origin = Point(center.x - targetSize.width / 2, center.y - targetSize.height / 2)
    let rect = Rect(origin: origin, size: targetSize)
    
    let tintWithOpacity = tint.withAlphaComponent(opacity)
    // Only show stroke when fully visible (opacity >= 0.99) to avoid fade glitches
    if opacity >= 0.99 {
      image.draw(in: rect, rotation: angle, tint: tintWithOpacity, strokeWidth: strokeWidth, strokeColor: strokeColor)
    } else {
      image.draw(in: rect, rotation: angle, tint: tintWithOpacity)
    }
  }

  func draw(in rect: Rect) {
    guard opacity > 0 else { return }
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
    
    let tintWithOpacity = tint.withAlphaComponent(opacity)
    // Only show stroke when fully visible (opacity >= 0.99) to avoid fade glitches
    if opacity >= 0.99 {
      image.draw(in: drawRect, rotation: angle, tint: tintWithOpacity, strokeWidth: strokeWidth, strokeColor: strokeColor)
    } else {
      image.draw(in: drawRect, rotation: angle, tint: tintWithOpacity)
    }
  }
}
