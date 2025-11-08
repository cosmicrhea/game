/// Global input state management
@MainActor
public final class Input {
  public static let player1 = Input()

  private var _isEnabled: Bool = true

  /// Whether input is enabled. Automatically includes ScreenFade state
  /// to prevent input during transitions. Set this synchronously to disable
  /// input immediately (e.g., before async operations).
  public var isEnabled: Bool {
    get {
      return _isEnabled && !ScreenFade.shared.isFading
    }
    set {
      _isEnabled = newValue
    }
  }

  private init() {}
}
