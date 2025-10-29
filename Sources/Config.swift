@MainActor
final class Config {
  static let current = Config()

  // Debug
  @ConfigValue("editor") var editorEnabled = false
  @ConfigValue("currentLoopIndex") var currentLoopIndex: Int = 0
  @ConfigValue("debugWireframe") var debugWireframe = false
  @ConfigValue("wireframeMode") var wireframeMode = false

  // Settings
  @ConfigValue("audio.uiVolume") var uiVolume: Float = 1.0
  @ConfigValue("volume") var volume: Double = 0.8
  @ConfigValue("resolution") var resolution: String = "1280x720"
  /// Persisted UI accent color as comma-separated RGBA floats
  @ConfigValue("accentRGBA") var accentRGBA: String = "0.3569,0.0471,0.0686,1.0"  // rose900
  // UI Layout
  @ConfigValue("centeredLayout") var centeredLayout: Bool = false
}
