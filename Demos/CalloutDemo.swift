import GL
import GLFW

@MainActor
final class CalloutDemo: RenderLoop {
  private var callouts: [Callout] = []
  private var isVisible: Bool = true
  private var animationTimer: Float = 0.0
  private let leftMargin: Float = 0
  private let topMargin: Float = 180
  private let verticalGap: Float = 16

  func onAttach(window: GLFWWindow) {
    // Create one callout per icon from the enum cases
    callouts = CalloutIcon.allCases.map { icon in
      Callout("Make your way to Kastellet (\(icon.rawValue))", icon: icon)
    }
    // Add a centered callout prompt
    callouts.append(Callout("Press WASD to move", icon: .chevron))
  }

  func update(deltaTime: Float) {
    // Auto-toggle visibility every 3 seconds for demo
    animationTimer += deltaTime
    if animationTimer >= 3.0 {
      isVisible.toggle()
      animationTimer = 0.0
    }

    for i in callouts.indices {
      callouts[i].visible = isVisible
      callouts[i].update(deltaTime: deltaTime)
    }
  }

  func draw() {
    // Top-left list
    var currentTop = Float(HEIGHT) - topMargin
    for i in 0..<callouts.count {
      if i == callouts.count - 1 { break }  // last is the centered prompt
      let rect = Rect(x: leftMargin, y: currentTop, width: 520, height: 32)
      callouts[i].draw(in: rect)
      currentTop -= (32 + verticalGap)
      if currentTop < 32 { break }
    }

    // Centered prompt
    if let centered = callouts.last {
      var c = centered
      c.draw(at: .center(yOffset: -128))
    }
  }
}
