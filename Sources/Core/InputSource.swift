/// Represents different input sources for the game.
public enum InputSource: String, CaseIterable, Sendable {
  /// Keyboard and mouse input.
  case keyboardMouse
  /// PlayStation controller input.
  case playstation
  /// Xbox controller input.
  case xbox
}

extension InputSource {
  nonisolated(unsafe) public static var player1 = Self.keyboardMouse
}

extension InputSource {
  /// The path to the input prompt atlas for this input source.
  public var inputPromptAtlasPath: String {
    switch self {
    case .keyboardMouse: return "UI/InputPrompts/keyboard-mouse.xml"
    case .playstation: return "UI/InputPrompts/playstation.xml"
    case .xbox: return "UI/InputPrompts/xbox.xml"
    }
  }

  /// Detects the input source from an icon name.
  /// - Parameter name: The icon name to analyze.
  /// - Returns: The detected input source, or `nil` if none could be determined.
  public static func detect(fromIconName name: String) -> InputSource? {
    if name.hasPrefix("keyboard") || name.hasPrefix("mouse") { return .keyboardMouse }
    if name.hasPrefix("playstation") { return .playstation }
    if name.hasPrefix("xbox") { return .xbox }
    return nil
  }

  /// Updates InputSource.player1 based on gamepad name.
  /// Detects Xbox or PlayStation controllers, defaults to PlayStation for unknown gamepads.
  /// - Parameter gamepad: The gamepad to detect the type from.
  @MainActor
  public static func updateFromGamepad(_ gamepad: Gamepad) {
    if let name = gamepad.gamepadName?.lowercased() {
      if name.contains("xbox") || name.contains("xinput") {
        InputSource.player1 = .xbox
      } else {
        InputSource.player1 = .playstation
      }
    } else {
      InputSource.player1 = .playstation
    }
  }
}
