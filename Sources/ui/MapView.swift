import GL
import GLFW
import GLMath

class MapView: RenderLoop, EditableObject {
  private var mapEffect: GLScreenEffect

  // Grid parameters
  @Editable(displayName: "Grid Scale", range: 0.1...3.0)
  var gridScale: Float = 1.0

  @Editable(displayName: "Grid Opacity", range: 0.0...1.0)
  var gridOpacity: Float = 0.8

  @Editable(displayName: "Vignette Strength", range: 0.0...1.0)
  var vignetteStrength: Float = 0.8

  @Editable(displayName: "Vignette Radius", range: 0.0...1.0)
  var vignetteRadius: Float = 0.9

  // Grid size control
  @Editable(displayName: "Grid Cell Size", range: 8.0...64.0)
  var gridCellSize: Float = 32.0  // Same as old hardcoded value

  // Color controls
  var backgroundColor: Color = .blueprintBackground
  var gridColor: Color = .blueprintGrid

  @Editable(displayName: "Grid Thickness", range: 0.5...3.0)
  var gridThickness: Float = 1.0  // 1 pixel thick

  init() {
    // Initialize simple GLScreenEffect
    self.mapEffect = GLScreenEffect("Common/MapView")
  }

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

  // MARK: - EditableObject Implementation
  func getEditableProperties() -> [AnyEditableProperty] {
    return [
      AnyEditableProperty(
        name: "Grid Scale",
        value: gridScale,
        setValue: { self.gridScale = $0 as! Float },
        displayName: "Grid Scale",
        validRange: 0.1...3.0
      ),
      AnyEditableProperty(
        name: "Grid Opacity",
        value: gridOpacity,
        setValue: { self.gridOpacity = $0 as! Float },
        displayName: "Grid Opacity",
        validRange: 0.0...1.0
      ),
      AnyEditableProperty(
        name: "Vignette Strength",
        value: vignetteStrength,
        setValue: { self.vignetteStrength = $0 as! Float },
        displayName: "Vignette Strength",
        validRange: 0.0...1.0
      ),
      AnyEditableProperty(
        name: "Vignette Radius",
        value: vignetteRadius,
        setValue: { self.vignetteRadius = $0 as! Float },
        displayName: "Vignette Radius",
        validRange: 0.0...1.0
      ),
      AnyEditableProperty(
        name: "Grid Cell Size",
        value: gridCellSize,
        setValue: { self.gridCellSize = $0 as! Float },
        displayName: "Grid Cell Size",
        validRange: 8.0...64.0
      ),
      AnyEditableProperty(
        name: "Grid Thickness",
        value: gridThickness,
        setValue: { self.gridThickness = $0 as! Float },
        displayName: "Grid Thickness",
        validRange: 0.5...3.0
      ),
    ]
  }
}

#if DEBUG
  import SwiftUI

  struct MapViewEditor: View {
    @State var vingetteStrength: Float = 0.5
    @State var vingetteOpacity: Float = 0.5

    var body: some View {
      Slider(value: $vingetteStrength) { Text("Vingette Strength") }
      Slider(value: $vingetteOpacity) { Text("Vingette Radius") }
    }
  }
#endif
