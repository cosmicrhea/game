import Foundation

final class CalloutDemo: RenderLoop {

  private let calloutRenderer = CalloutRenderer()
  private let arrowRight = ImageRenderer("UI/Arrows/curved-right.png")

  @MainActor func draw() {
    // First callout
    calloutRenderer.size = (520, 44)
    calloutRenderer.position = (0, Float(HEIGHT) - 64)
    calloutRenderer.anchor = .topLeft
    calloutRenderer.fade = .right
    calloutRenderer.label = "Escape the lab"
    calloutRenderer.icon = nil
    calloutRenderer.draw(windowSize: (Int32(WIDTH), Int32(HEIGHT)))

    // Second, taller callout with icon and both fades
    calloutRenderer.size = (520, 96)
    calloutRenderer.position = (0, Float(HEIGHT) - 64 - 44 - 12)
    calloutRenderer.anchor = .topLeft
    calloutRenderer.fade = .both
    calloutRenderer.label = "Find the key in the storage room"
    calloutRenderer.icon = arrowRight
    calloutRenderer.iconSize = (32, 32)
    calloutRenderer.draw(windowSize: (Int32(WIDTH), Int32(HEIGHT)))
  }
}
