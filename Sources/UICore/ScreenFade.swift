import GL
import GLFW
import GLMath

/// A global screen fade system for transitions
@MainActor
public final class ScreenFade {
  public static let shared = ScreenFade()

  private var currentOpacity: Float = 0.0
  private var targetOpacity: Float = 0.0
  private var startOpacity: Float = 0.0
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var animationDuration: Float = 0.3
  private let animationEasing: Easing = .easeInOutCubic

  private init() {}

  /// Start a fade to black transition
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  /// - Parameter completion: Optional callback when fade completes
  public func fadeToBlack(duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = 1.0
    animationDuration = duration
    startAnimation(completion: completion)
  }

  /// Start a fade from black transition
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  /// - Parameter completion: Optional callback when fade completes
  public func fadeFromBlack(duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = 0.0
    animationDuration = duration
    startAnimation(completion: completion)
  }

  /// Start a fade to a specific opacity
  /// - Parameters:
  ///   - opacity: Target opacity (0.0 = transparent, 1.0 = opaque)
  ///   - duration: How long the fade should take
  ///   - completion: Optional callback when fade completes
  public func fadeToOpacity(_ opacity: Float, duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = opacity
    animationDuration = duration
    startAnimation(completion: completion)
  }

  /// Check if the overlay is currently visible (opacity > 0)
  public var isVisible: Bool {
    return currentOpacity > 0.0
  }

  /// Get the current opacity value
  public var opacity: Float {
    return currentOpacity
  }

  /// Reset the fade to transparent state
  public func reset() {
    currentOpacity = 0.0
    targetOpacity = 0.0
    startOpacity = 0.0
    isAnimating = false
    animationTime = 0.0
    completionCallback = nil
  }

  /// Update the fade animation
  /// - Parameter deltaTime: Time since last frame
  public func update(deltaTime: Float) {
    guard isAnimating else { return }

    animationTime += deltaTime
    let progress = min(animationTime / animationDuration, 1.0)
    let easedProgress = animationEasing.apply(progress)

    // Interpolate between start and target opacity
    currentOpacity = startOpacity + (targetOpacity - startOpacity) * easedProgress

    if progress >= 1.0 {
      isAnimating = false
      animationTime = 0.0
      currentOpacity = targetOpacity
      completionCallback?()
      completionCallback = nil
    }
  }

  /// Draw the fade overlay
  /// - Parameters:
  ///   - screenSize: The size of the screen to cover
  public func draw(screenSize: Size) {
    guard currentOpacity > 0.0 else { return }

    let overlayRect = Rect(origin: .zero, size: screenSize)

    // Use a dark color that gets darker as opacity increases
    let intensity = 1.0 - currentOpacity  // Invert so 0 opacity = white, 1 opacity = black
    let overlayColor = Color(red: intensity, green: intensity, blue: intensity, alpha: 1.0)

    // Draw a rectangle covering the entire screen
    if let context = GraphicsContext.current {
      var path = BezierPath()
      path.addRect(overlayRect)
      context.drawPath(path, color: overlayColor)
    }
  }

  // MARK: - Private

  private var completionCallback: (() -> Void)?

  private func startAnimation(completion: (() -> Void)?) {
    startOpacity = currentOpacity
    isAnimating = true
    animationTime = 0.0
    completionCallback = completion
  }
}
