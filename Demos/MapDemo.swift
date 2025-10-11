import GL
import GLFW
import GLMath

@MainActor
final class MapDemo: RenderLoop {
  var mapView: MapView

  init() {
    self.mapView = MapView()
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .r:
      mapView.gridScale *= 1.2
      UISound.select()
    case .space:
      mapView.gridScale *= 0.8
      UISound.select()
    case .g:
      mapView.gridOpacity = mapView.gridOpacity > 0.5 ? 0.3 : 0.8
      UISound.select()
    case .v:
      // Toggle vignette strength
      mapView.vignetteStrength = mapView.vignetteStrength > 0.5 ? 0.2 : 0.8
      UISound.select()
    case .b:
      // Toggle vignette radius
      mapView.vignetteRadius = mapView.vignetteRadius > 0.5 ? 0.3 : 0.8
      UISound.select()
    case .c:
      // Cycle through grid colors
      if mapView.gridColor == .blueprintGrid {
        mapView.gridColor = .white
      } else if mapView.gridColor == .white {
        mapView.gridColor = .gray300
      } else {
        mapView.gridColor = .blueprintGrid
      }
      UISound.select()
    case .t:
      // Toggle grid thickness
      mapView.gridThickness = mapView.gridThickness > 1.0 ? 0.5 : 2.0
      UISound.select()
    default:
      break
    }
  }

  func draw() {
    mapView.draw()
  }
}
