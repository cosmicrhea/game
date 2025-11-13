import Jolt

final class DebugRendererImplementation: DebugRendererProcs {
  weak var renderLoop: MainLoop?

  func drawLine(from: RVec3, to: RVec3, color: Jolt.Color) {
    guard let renderLoop = renderLoop else { return }
    let fromVec = vec3(Float(from.x), Float(from.y), Float(from.z))
    let toVec = vec3(Float(to.x), Float(to.y), Float(to.z))

    // Convert Jolt.Color (RGBA packed UInt32) to Color
    let lineColor = Color(color)

    MainActor.assumeIsolated {
      // Use GLRenderer directly instead of drawDebugLine
      guard let renderer = GraphicsContext.current?.renderer as? GLRenderer else { return }
      renderer.drawDebugLine3D(
        from: fromVec,
        to: toVec,
        color: lineColor,
        projection: renderLoop.currentProjection,
        view: renderLoop.currentView,
        lineThickness: 0.005,  // Thin line for wireframe
        depthTest: false  // Always on top for debug overlay
      )
    }
  }

  func drawTriangle(
    v1: RVec3, v2: RVec3, v3: RVec3, color: Jolt.Color, castShadow: DebugRenderer.CastShadow
  ) {
    // Draw triangle as wireframe using lines
    drawLine(from: v1, to: v2, color: color)
    drawLine(from: v2, to: v3, color: color)
    drawLine(from: v3, to: v1, color: color)
  }

  func drawText3D(position: RVec3, text: String, color: Jolt.Color, height: Float) {
    logger.trace("\(#function) \(text)")
    // For now, just ignore text rendering
    // TODO: Implement 3D text rendering if needed
  }
}
