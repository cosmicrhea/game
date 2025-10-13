import GL
import GLFW

@MainActor
final class CalloutDemo: RenderLoop {
  private var objectiveCallouts: [Callout] = []
  private var tutorialCallout: Callout?
  private var promptListCallout: Callout?

  private var isVisible: Bool = true
  private var animationTimer: Float = 0.0
  private var staggerTimer: Float = 0.0
  private let verticalGap: Float = 16
  private let staggerDelay: Float = 0.15  // Delay between each callout animation

  func onAttach(window: GLFWWindow) {
    // Create objective callouts for each icon
    objectiveCallouts = CalloutIcon.allCases.map { icon in
      Callout("Make your way to Kastellet", icon: icon)
    }

    // Create tutorial callout
    tutorialCallout = Callout("Press WASD to move", style: .tutorial)

    // Create prompt list callout
    var promptList = Callout(style: .promptList())
    promptList.fade = .left
    promptListCallout = promptList
  }

  func update(deltaTime: Float) {
    // Auto-toggle visibility every 3 seconds for demo
    animationTimer += deltaTime
    if animationTimer >= 3.0 {
      isVisible.toggle()
      animationTimer = 0.0
      staggerTimer = 0.0  // Reset stagger timer when toggling
    }

    // Staggered visibility updates for objective callouts
    staggerTimer += deltaTime

    for i in objectiveCallouts.indices {
      let staggerOffset = Float(i) * staggerDelay
      let shouldBeVisible: Bool

      if isVisible {
        // Staggered showing: each callout appears after its delay
        shouldBeVisible = staggerTimer >= staggerOffset
      } else {
        // Staggered hiding: each callout disappears after its delay
        shouldBeVisible = staggerTimer < staggerOffset
      }

      objectiveCallouts[i].visible = shouldBeVisible
      objectiveCallouts[i].update(deltaTime: deltaTime)
    }

    // Update tutorial callout
    if var tutorial = tutorialCallout {
      tutorial.visible = isVisible
      tutorial.update(deltaTime: deltaTime)
      tutorialCallout = tutorial
    }

    // Keep prompt list callout always visible and not animated
    if var promptList = promptListCallout {
      promptList.visible = true
      // Don't call update() on it to prevent animation
      promptListCallout = promptList
    }
  }

  func draw() {
    // Draw objective callouts (top-left, stacked)
    var currentTop: Float = 0
    for i in objectiveCallouts.indices {
      var callout = objectiveCallouts[i]
      callout.style = .objective(offset: currentTop)
      callout.draw()
      currentTop += (callout.size.height + verticalGap)
    }

    // Draw tutorial callout (centered)
    if var tutorial = tutorialCallout {
      tutorial.draw()
    }

    // Draw prompt list callout (bottom-right, static)
    if var promptList = promptListCallout {
      promptList.draw()
    }
  }
}
