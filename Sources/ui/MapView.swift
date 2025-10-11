import GL
import GLFW
import GLMath

@Editor(.grouped)
class MapView: RenderLoop {
  private var mapEffect = GLScreenEffect("Common/MapView")

  @Editable(range: 8.0...64.0) var gridCellSize: Float = 32.0
  @Editable(range: 0.5...3.0) var gridThickness: Float = 1.0
  @Editable(range: 0.1...3.0) var gridScale: Float = 1.0
  @Editable var gridOpacity: Float = 0.8

  @Editable var vignetteStrength: Float = 0.8
  @Editable var vignetteRadius: Float = 0.9

  var backgroundColor: Color = .blueprintBackground
  var gridColor: Color = .blueprintGrid

  func update(deltaTime: Float) {
    // Update any animations or effects
    // For now, just a placeholder
  }

  func draw() {
    mapEffect.draw { shader in
      shader.setFloat("uGridScale", value: gridScale)
      shader.setFloat("uGridOpacity", value: gridOpacity)
      shader.setFloat("uVignetteStrength", value: vignetteStrength)
      shader.setFloat("uVignetteRadius", value: vignetteRadius)
      shader.setFloat("uGridCellSize", value: gridCellSize)
      shader.setColor("uBackgroundColor", value: backgroundColor)
      shader.setColor("uGridColor", value: gridColor)
      shader.setFloat("uGridThickness", value: gridThickness)
    }
  }
}
