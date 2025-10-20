import GLFW

/// Base class for screens with built-in navigation capabilities
@MainActor
class Screen: RenderLoop {
  /// Navigation stack gets injected by NavigationStack when screens are pushed
  var navigationStack: NavigationStack?
  //  {
  //    didSet {
  //      print("🎯 Screen.navigationStack set: \(navigationStack != nil ? "present" : "nil")")
  //    }
  //  }

  // MARK: - Initialization

  init() {
    // Base initialization
  }

  // MARK: - RenderLoop Implementation

  func update(deltaTime: Float) {
    // Override in subclasses
  }

  func update(window: Window, deltaTime: Float) {
    // Override in subclasses
  }

  func draw() {
    // Override in subclasses
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Override in subclasses
  }

  func onMouseButtonPressed(window: GLFWWindow, button: Mouse.Button, mods: Keyboard.Modifier) {
    // Override in subclasses
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    // Override in subclasses
  }

  func onAttach(window: Window) {
    // Override in subclasses
  }

  func onDetach(window: Window) {
    // Override in subclasses
  }

  // MARK: - Navigation Methods

  /// Navigate to a new screen
  func navigate(to screen: Screen, direction: NavigationStack.TransitionDirection = .forward) {
    //print("🎯 Screen.navigate() called - navigationStack: \(navigationStack != nil ? "present" : "nil")")
    navigationStack?.push(screen, direction: direction)
    //print("🎯 Screen.navigate() - push() called")
  }

  /// Go back to the previous screen
  func back() {
    navigationStack?.pop()
  }

  /// Replace current screen with a new one
  func replace(with screen: Screen) {
    navigationStack?.replace(screen)
  }
}
