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
}
