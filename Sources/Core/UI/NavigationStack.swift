/// A navigation stack that manages multiple RenderLoops with smooth transitions
@MainActor
public class NavigationStack: RenderLoop {

  // MARK: - Properties
  private struct Entry {
    let screen: Screen
    let usesFullScreen: Bool
  }

  private var entries: [Entry] = []
  private var currentIndex: Int = 0
  private var isTransitioning: Bool = false
  private var isFullScreenTransition: Bool = false

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
    let count = entries.count
    return count <= 1 || (isTransitioning && transitionDirection == .backward && count <= 2)
  }

  /// Indicates whether the active screen wants exclusive/full-screen presentation.
  var usesFullScreenContent: Bool {
    return activeEntry?.usesFullScreen ?? false
  }

  var activeScreen: Screen? {
    return activeEntry?.screen
  }

  private var activeEntry: Entry? {
    guard entries.indices.contains(currentIndex) else { return nil }
    return entries[currentIndex]
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
  func push(
    _ screen: Screen,
    direction: TransitionDirection = .forward,
    usesFullScreen: Bool = false
  ) {
    guard !isTransitioning else {
      return
    }

    screen.navigationStack = self

    let requiresFullScreenTransition = usesFullScreen || activeEntry?.usesFullScreen == true
    if requiresFullScreenTransition {
      let entry = Entry(screen: screen, usesFullScreen: usesFullScreen)
      performFullScreenTransition(direction: direction) {
        self.entries.append(entry)
        self.currentIndex = self.entries.count - 1
        entry.screen.onAttach(window: Engine.shared.window)
      }
      return
    }

    entries.append(Entry(screen: screen, usesFullScreen: usesFullScreen))
    transitionDirection = direction
    isTransitioning = true
    isFullScreenTransition = false
    transitionProgress = 0.0
    screenSize = Engine.viewportSize
    screen.onAttach(window: Engine.shared.window)
  }

  /// Pop the current screen and go back to the previous one
  public func pop() {
    guard entries.count > 1 else {
      return
    }
    guard !isTransitioning else {
      return
    }

    transitionDirection = .backward

    let requiresFullScreenTransition =
      entries.last?.usesFullScreen == true
      || entries[entries.count - 2].usesFullScreen == true
    if requiresFullScreenTransition {
      performFullScreenTransition(direction: .backward) {
        let removedEntry = self.entries.removeLast()
        removedEntry.screen.onDetach(window: Engine.shared.window)
        self.currentIndex = max(0, self.entries.count - 1)
      }
      return
    }

    isTransitioning = true
    isFullScreenTransition = false
    transitionProgress = 0.0
  }

  /// Replace the current screen with a new one
  func replace(_ screen: Screen, usesFullScreen: Bool = false) {
    guard !isTransitioning else {
      return
    }

    screen.navigationStack = self

    let requiresFullScreenTransition = usesFullScreen || activeEntry?.usesFullScreen == true

    if requiresFullScreenTransition {
      performFullScreenTransition(direction: .forward) {
        if self.entries.indices.contains(self.currentIndex) {
          let oldEntry = self.entries[self.currentIndex]
          oldEntry.screen.onDetach(window: Engine.shared.window)
          self.entries[self.currentIndex] = Entry(screen: screen, usesFullScreen: usesFullScreen)
        } else {
          self.entries.append(Entry(screen: screen, usesFullScreen: usesFullScreen))
          self.currentIndex = self.entries.count - 1
        }
        screen.onAttach(window: Engine.shared.window)
      }
      return
    }

    if entries.indices.contains(currentIndex) {
      entries[currentIndex] = Entry(screen: screen, usesFullScreen: usesFullScreen)
    } else {
      entries.append(Entry(screen: screen, usesFullScreen: usesFullScreen))
      currentIndex = entries.count - 1
    }

    transitionDirection = .forward
    isTransitioning = true
    isFullScreenTransition = false
    transitionProgress = 0.0
  }

  /// Set the initial screen
  func setInitialScreen(_ screen: Screen, usesFullScreen: Bool = false) {
    screen.navigationStack = self

    entries = [Entry(screen: screen, usesFullScreen: usesFullScreen)]
    currentIndex = 0
    screen.onAttach(window: Engine.shared.window)
  }

  // MARK: - RenderLoop Implementation

  public func update(deltaTime: Float) {
    if let entry = activeEntry {
      entry.screen.update(deltaTime: deltaTime)
    }

    if isTransitioning && !isFullScreenTransition {
      transitionProgress += deltaTime / transitionDuration

      if transitionProgress >= 1.0 {
        completeTransition()
      }
    }
  }

  public func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    guard !isTransitioning, let entry = activeEntry else {
      return
    }

    entry.screen.onKeyPressed(window: window, key: key, scancode: scancode, mods: mods)
  }

  public func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard !isTransitioning, let entry = activeEntry else {
      return
    }

    entry.screen.onMouseButtonPressed(window: window, button: button, mods: mods)
  }

  public func onMouseMove(window: Window, x: Double, y: Double) {
    guard !isTransitioning, let entry = activeEntry else {
      return
    }

    entry.screen.onMouseMove(window: window, x: x, y: y)
  }

  public func draw() {
    if isTransitioning {
      if isFullScreenTransition {
        activeEntry?.screen.draw()
        return
      }
      drawTransition()
    } else {
      activeEntry?.screen.draw()
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
    isFullScreenTransition = false
    transitionProgress = 0.0

    if transitionDirection == .forward {
      currentIndex = max(0, entries.count - 1)
    } else {
      if entries.count > 1 {
        let removedEntry = entries.removeLast()
        removedEntry.screen.onDetach(window: Engine.shared.window)
        currentIndex = max(0, entries.count - 1)
      }
    }
  }

  private func performFullScreenTransition(
    direction: TransitionDirection,
    transitionBlock: @escaping () -> Void
  ) {
    transitionDirection = direction
    isTransitioning = true
    isFullScreenTransition = true
    transitionProgress = 0.0
    screenSize = Engine.viewportSize

    Task { @MainActor in
      await ScreenFade.shared.fadeToBlack(duration: transitionDuration)
      transitionBlock()
      await ScreenFade.shared.fadeFromBlack(duration: transitionDuration)
      isTransitioning = false
      isFullScreenTransition = false
      transitionProgress = 0.0
    }
  }

  private func drawTransition() {
    guard entries.count >= 1 else {
      return
    }

    let currentEntry: Entry
    let nextEntry: Entry

    if transitionDirection == .forward {
      guard entries.count >= 2 else {
        return
      }
      currentEntry = entries[currentIndex]
      nextEntry = entries.last!
    } else {
      guard entries.count >= 2 else {
        return
      }
      currentEntry = entries.last!  // Current screen (being removed)
      nextEntry = entries[entries.count - 2]  // Previous screen (going back to)
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
    nextEntry.screen.update(deltaTime: 0.016)  // Use a small delta time for animations

    // Render current screen to FBO
    if let currentFBO = currentScreenFBO {
      Engine.shared.renderer.beginFramebuffer(currentFBO)
      currentEntry.screen.draw()
      Engine.shared.renderer.endFramebuffer()
    }

    // Render next screen to FBO (live update for animations)
    if let nextFBO = nextScreenFBO {
      Engine.shared.renderer.beginFramebuffer(nextFBO)
      nextEntry.screen.draw()
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
