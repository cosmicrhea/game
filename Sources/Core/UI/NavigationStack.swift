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
    print("🚀 NavigationStack.push() called - direction: \(direction)")
    guard !isTransitioning else {
      print("🚀 Already transitioning, ignoring")
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
    print("🚀 Screen size: \(screenSize)")

    // Attach the new screen
    screen.onAttach(window: Engine.shared.window)
    print("🚀 Transition started")
  }

  /// Pop the current screen and go back to the previous one
  public func pop() {
    print("🔙 NavigationStack.pop() called - screens count: \(screens.count)")
    guard screens.count > 1 else {
      print("🔙 Can't pop - only one screen")
      return
    }
    guard !isTransitioning else {
      print("🔙 Can't pop - already transitioning")
      return
    }

    // Start transition back (don't remove screen yet)
    transitionDirection = .backward
    isTransitioning = true
    transitionProgress = 0.0
    print("🔙 Started backward transition")
  }

  /// Replace the current screen with a new one
  func replace(_ screen: Screen) {
    print("🔄 NavigationStack.replace() called")
    guard !isTransitioning else {
      print("🔄 Can't replace - already transitioning")
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
    print("🔄 Started replace transition")
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
      print("🎬 Transition progress: \(transitionProgress)")

      if transitionProgress >= 1.0 {
        print("🎬 Transition complete")
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
      print("🎨 Drawing transition")
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
        print("🔙 Removed screen after transition, remaining: \(screens.count)")
        print("🔙 Current screen is now: \(type(of: screens.last!)) at index \(currentIndex)")
      }
    }
  }

  private func drawTransition() {
    guard screens.count >= 1 else {
      print("🎨 No screens for transition")
      return
    }

    let currentScreen: RenderLoop
    let nextScreen: RenderLoop

    if transitionDirection == .forward {
      guard screens.count >= 2 else {
        print("🎨 Not enough screens for forward transition")
        return
      }
      currentScreen = screens[currentIndex]
      nextScreen = screens.last!
    } else {
      guard screens.count >= 2 else {
        print("🎨 Not enough screens for backward transition")
        return
      }
      currentScreen = screens.last!  // Current screen (being removed)
      nextScreen = screens[screens.count - 2]  // Previous screen (going back to)
      print("🎨 Backward transition: current=\(type(of: currentScreen)), next=\(type(of: nextScreen))")
    }

    // Create FBOs if they don't exist
    if currentScreenFBO == nil {
      currentScreenFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)
      print("🎨 Created currentScreenFBO: \(currentScreenFBO ?? 0)")
    }
    if nextScreenFBO == nil {
      nextScreenFBO = Engine.shared.renderer.createFramebuffer(size: screenSize, scale: 1.0)
      print("🎨 Created nextScreenFBO: \(nextScreenFBO ?? 0)")
    }

    // Calculate eased progress
    let easedProgress = transitionEasing.apply(transitionProgress)
    print("🎨 Eased progress: \(easedProgress)")

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
      print("🎨 Rendering next screen to FBO: \(nextFBO)")
      Engine.shared.renderer.beginFramebuffer(nextFBO)
      nextScreen.draw()
      Engine.shared.renderer.endFramebuffer()
    } else {
      print("🎨 No next FBO to render to!")
    }

    // Calculate slide offsets
    let screenWidth = screenSize.width
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

    print("🎨 Current offset: \(currentOffset), alpha: \(currentAlpha)")
    print("🎨 Next offset: \(nextOffset), alpha: \(nextAlpha)")
    print("🎨 Next screen type: \(type(of: nextScreen))")

    // Draw current screen (sliding left, fading out)
    if let currentFBO = currentScreenFBO {
      let currentTransform = Transform2D(
        translation: Point(-currentOffset, 0),
        rotation: 0,
        scale: Point(1, 1)
      )
      print("🎨 Drawing current FBO with transform: \(currentTransform.translation)")
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
      print("🎨 Next screen: startX=\(nextStartX), offset=\(nextOffset), finalX=\(nextX), alpha=\(nextAlpha)")
      Engine.shared.renderer.drawFramebuffer(
        nextFBO,
        in: Rect(x: 0, y: 0, width: screenSize.width, height: screenSize.height),
        transform: nextTransform,
        alpha: nextAlpha
      )
    } else {
      print("🎨 No next FBO available!")
    }
  }
}
