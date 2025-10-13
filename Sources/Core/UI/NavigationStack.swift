import GLFW

/// A navigation stack that manages multiple RenderLoops with smooth transitions
@MainActor
public class NavigationStack: RenderLoop {

  // MARK: - Properties
  private var screens: [RenderLoop] = []
  private var currentIndex: Int = 0
  private var isTransitioning: Bool = false

  // MARK: - Transition Animation
  private var transitionProgress: Float = 0.0
  private var transitionDuration: Float = 0.3
  private var transitionDirection: TransitionDirection = .forward
  private let transitionEasing: Easing = .easeInOutCubic

  // MARK: - FBO for transitions
  private var currentScreenFBO: UInt64?
  private var nextScreenFBO: UInt64?
  private var screenSize: Size = Size(0, 0)

  // MARK: - Navigation State

  /// Whether we're at the root screen (only one screen in the stack, or transitioning back to root)
  var isAtRoot: Bool {
    return screens.count <= 1 || (isTransitioning && transitionDirection == .backward && screens.count <= 2)
  }

  public enum TransitionDirection {
    case forward  // New screen slides in from right
    case backward  // New screen slides in from left
  }

  // MARK: - Initialization

  public init() {
  }

  // MARK: - Navigation Methods

  /// Push a new screen onto the stack
  func push(_ screen: Screen, direction: TransitionDirection = .forward) {
    guard !isTransitioning else {
      return
    }

    // Inject navigation stack into the screen
    screen.navigationStack = self

    screens.append(screen)
    transitionDirection = direction
    isTransitioning = true
    transitionProgress = 0.0

    // Set up screen size for FBO
    screenSize = Size(Float(WIDTH), Float(HEIGHT))

    // Attach the new screen
    screen.onAttach(window: Engine.shared.window)
  }

  /// Pop the current screen and go back to the previous one
  public func pop() {
    guard screens.count > 1 else {
      return
    }
    guard !isTransitioning else {
      return
    }

    // Start transition back (don't remove screen yet)
    transitionDirection = .backward
    isTransitioning = true
    transitionProgress = 0.0
  }

  /// Replace the current screen with a new one
  func replace(_ screen: Screen) {
    guard !isTransitioning else {
      return
    }

    // Inject navigation stack into the screen
    screen.navigationStack = self

    // Replace the current screen
    if currentIndex < screens.count {
      screens[currentIndex] = screen
    } else {
      screens.append(screen)
    }

    // Start transition
    transitionDirection = .forward
    isTransitioning = true
    transitionProgress = 0.0
  }

  /// Set the initial screen
  func setInitialScreen(_ screen: Screen) {
    // Inject navigation stack into the initial screen
    screen.navigationStack = self

    screens = [screen]
    currentIndex = 0
    screen.onAttach(window: Engine.shared.window)
  }

  // MARK: - RenderLoop Implementation

  public func update(deltaTime: Float) {
    // Update current screen
    if currentIndex < screens.count {
      screens[currentIndex].update(deltaTime: deltaTime)
    }

    // Update transition
    if isTransitioning {
      transitionProgress += deltaTime / transitionDuration

      if transitionProgress >= 1.0 {
        completeTransition()
      }
    }
  }

  public func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    if isTransitioning {
      // Don't handle input during transitions
      return
    }

    if currentIndex < screens.count {
      screens[currentIndex].onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
    }
  }

  public func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    if isTransitioning {
      return
    }

    if currentIndex < screens.count {
      screens[currentIndex].onMouseButtonPressed(window: window, button: button, mods: mods)
    }
  }

  public func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    if isTransitioning {
      return
    }

    if currentIndex < screens.count {
      screens[currentIndex].onMouseMove(window: window, x: x, y: y)
    }
  }

  public func draw() {
    if isTransitioning {
      drawTransition()
    } else {
      // Draw current screen
      if currentIndex < screens.count {
        screens[currentIndex].draw()
      }
    }
  }

  // MARK: - Private Methods

  private func completeTransition() {
    // Clean up FBOs
    if let currentFBO = currentScreenFBO {
      Engine.shared.renderer.destroyFramebuffer(currentFBO)
    }
    if let nextFBO = nextScreenFBO {
      Engine.shared.renderer.destroyFramebuffer(nextFBO)
    }
    currentScreenFBO = nil
    nextScreenFBO = nil

    isTransitioning = false
    transitionProgress = 0.0

    if transitionDirection == .forward {
      currentIndex = screens.count - 1
    } else {
      // Remove the current screen after backward transition
      if screens.count > 1 {
        let removedScreen = screens.removeLast()
        removedScreen.onDetach(window: Engine.shared.window)
        // Update currentIndex to point to the new last screen
        currentIndex = screens.count - 1
      }
    }
  }

  private func drawTransition() {
    guard screens.count >= 1 else {
      return
    }

    let currentScreen: RenderLoop
    let nextScreen: RenderLoop

    if transitionDirection == .forward {
      guard screens.count >= 2 else {
        return
      }
      currentScreen = screens[currentIndex]
      nextScreen = screens.last!
    } else {
      guard screens.count >= 2 else {
        return
      }
      currentScreen = screens.last!  // Current screen (being removed)
      nextScreen = screens[screens.count - 2]  // Previous screen (going back to)
    }

    // Create FBOs if they don't exist
    if currentScreenFBO == nil {
      currentScreenFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)
    }
    if nextScreenFBO == nil {
      nextScreenFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)
    }

    // Calculate eased progress
    let easedProgress = transitionEasing.apply(transitionProgress)

    // Update next screen for live animations during transition
    nextScreen.update(deltaTime: 0.016)  // Use a small delta time for animations

    // Render current screen to FBO
    if let currentFBO = currentScreenFBO {
      Engine.shared.renderer.beginFramebuffer(currentFBO)
      currentScreen.draw()
      Engine.shared.renderer.endFramebuffer()
    }

    // Render next screen to FBO (live update for animations)
    if let nextFBO = nextScreenFBO {
      Engine.shared.renderer.beginFramebuffer(nextFBO)
      nextScreen.draw()
      Engine.shared.renderer.endFramebuffer()
    } else {
    }

    // Calculate slide offsets
    let slideDistance: Float = 10.0

    let currentOffset: Float
    let nextOffset: Float

    if transitionDirection == .forward {
      // Forward: current slides left, next slides in from right
      currentOffset = slideDistance * easedProgress  // Start at 0, move to slideDistance
      nextOffset = slideDistance * easedProgress  // Start at 0, move to slideDistance (but next screen starts at slideDistance)
    } else {
      // Backward: current slides right, next slides in from left
      currentOffset = -slideDistance * easedProgress  // Start at 0, move to -slideDistance
      nextOffset = -slideDistance * easedProgress  // Start at 0, move to -slideDistance (but next screen starts at -slideDistance)
    }

    // Calculate alpha values
    let currentAlpha = 1.0 - easedProgress
    let nextAlpha = easedProgress

    // Draw current screen (sliding left, fading out)
    if let currentFBO = currentScreenFBO {
      let currentTransform = Transform2D(
        translation: Point(-currentOffset, 0),
        rotation: 0,
        scale: Point(1, 1)
      )
      Engine.shared.renderer.drawFramebuffer(
        currentFBO,
        in: Rect(x: 0, y: 0, width: screenSize.width, height: screenSize.height),
        transform: currentTransform,
        alpha: currentAlpha
      )
    }

    // Draw next screen (sliding in from right, fading in)
    if let nextFBO = nextScreenFBO {
      let nextStartX = transitionDirection == .forward ? slideDistance : -slideDistance
      let nextX = nextStartX - nextOffset
      let nextTransform = Transform2D(
        translation: Point(nextX, 0),
        rotation: 0,
        scale: Point(1, 1)
      )
      Engine.shared.renderer.drawFramebuffer(
        nextFBO,
        in: Rect(x: 0, y: 0, width: screenSize.width, height: screenSize.height),
        transform: nextTransform,
        alpha: nextAlpha
      )
    } else {
    }
  }
}
