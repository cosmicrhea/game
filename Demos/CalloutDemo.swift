import GL
import GLFW

@MainActor
final class CalloutDemo: RenderLoop {
  private var callouts: [Callout] = []
  private var isVisible: Bool = true
  private var animationTimer: Float = 0.0
  private var staggerTimer: Float = 0.0
  private let leftMargin: Float = 0
  private let topMargin: Float = 180
  private let verticalGap: Float = 16
  private let staggerDelay: Float = 0.15  // Delay between each callout animation

  func onAttach(window: GLFWWindow) {
    // Create one callout per icon from the enum cases
    callouts = CalloutIcon.allCases.map { icon in
      Callout("Make your way to Kastellet", icon: icon)
    }

    // Add a centered callout prompt
    callouts.append(Callout("Press WASD to move"))
  }

  func update(deltaTime: Float) {
    // Auto-toggle visibility every 3 seconds for demo
    animationTimer += deltaTime
    if animationTimer >= 3.0 {
      isVisible.toggle()
      animationTimer = 0.0
      staggerTimer = 0.0  // Reset stagger timer when toggling
    }

    // Staggered visibility updates
    staggerTimer += deltaTime

    for i in callouts.indices {
      let staggerOffset = Float(i) * staggerDelay
      let shouldBeVisible = isVisible && staggerTimer >= staggerOffset

      callouts[i].visible = shouldBeVisible
      callouts[i].update(deltaTime: deltaTime)
    }
  }

  func draw() {
    // Top-left list
    var currentTop: Float = 0
    for i in 0..<callouts.count {
      if i == callouts.count - 1 { break }  // last is the centered prompt
      //let rect = Rect(x: leftMargin, y: currentTop, width: 520, height: 36)
      callouts[i].draw(at: .topLeft(yOffset: -currentTop))
      currentTop += (36 + verticalGap)
//      if currentTop < 36 { break }
    }

    // Centered prompt
    if let centered = callouts.last {
      var c = centered
      c.fade = .both
      c.draw(at: .center(yOffset: 128))
    }
  }
}
