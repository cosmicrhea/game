import Foundation

/// A global screen shake system for camera shake effects
@MainActor
public final class ScreenShake {
  public static let shared = ScreenShake()

  /// Intensity levels for screen shake
  public enum Intensity: Float {
    case subtle = 3.0
    case heavy = 9.0
  }

  private var shakeTimeRemaining: Float = 0.0
  private var shakeIntensity: Float = 0.0
  private var shakeAxis: Axis?
  private var currentOffset: Point = .zero
  private var shakeDuration: Float = 0.0

  private init() {}

  /// Calculate duration based on intensity (heavier shakes last longer)
  private func durationForIntensity(_ intensity: Float) -> Float {
    // Base duration of 0.1 seconds, plus 0.1 seconds per unit of intensity
    // This gives: subtle (0.5) = 0.15s, heavy (2.0) = 0.3s
    return 0.1 + (intensity * 0.1)
  }

  /// Start a screen shake effect
  /// - Parameters:
  ///   - intensity: The intensity of the shake (.subtle or .heavy)
  ///   - axis: Optional axis to limit shake to (.horizontal or .vertical). If nil, shakes on both axes.
  public func shake(_ intensity: Intensity, axis: Axis? = nil) {
    shakeIntensity = intensity.rawValue
    shakeAxis = axis
    shakeDuration = durationForIntensity(intensity.rawValue)
    shakeTimeRemaining = shakeDuration
  }

  /// Get the current shake offset to apply to the view matrix
  public var offset: Point {
    return currentOffset
  }

  /// Check if shake is currently active
  public var isActive: Bool {
    return shakeTimeRemaining > 0.0
  }

  /// Update the shake animation
  /// - Parameter deltaTime: Time since last frame
  public func update(deltaTime: Float) {
    guard shakeTimeRemaining > 0.0 else {
      currentOffset = .zero
      return
    }

    shakeTimeRemaining -= deltaTime

    // Calculate shake strength (decay over time)
    // Clamp progress to [0, 1] to prevent negative strength values
    let progress = max(0.0, min(1.0, shakeTimeRemaining / shakeDuration))
    let strength = shakeIntensity * progress

    // Only generate shake if strength is positive
    guard strength > 0.0 else {
      currentOffset = .zero
      shakeTimeRemaining = 0.0
      return
    }

    // Generate random offset based on intensity and axis
    let randomX: Float
    let randomY: Float

    if let axis = shakeAxis {
      switch axis {
      case .horizontal:
        randomX = Float.random(in: -strength...strength)
        randomY = 0.0
      case .vertical:
        randomX = 0.0
        randomY = Float.random(in: -strength...strength)
      }
    } else {
      // Shake on both axes
      randomX = Float.random(in: -strength...strength)
      randomY = Float.random(in: -strength...strength)
    }

    currentOffset = Point(randomX, randomY)

    if shakeTimeRemaining <= 0.0 {
      shakeTimeRemaining = 0.0
      currentOffset = .zero
    }
  }

  /// Reset the shake to inactive state
  public func reset() {
    shakeTimeRemaining = 0.0
    shakeIntensity = 0.0
    shakeAxis = nil
    currentOffset = .zero
  }
}
