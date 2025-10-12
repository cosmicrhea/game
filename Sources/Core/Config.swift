@MainActor
final class Config {
  static let current = Config()

  // Debug
  @ConfigValue("editor") var editorEnabled = false
  @ConfigValue("currentLoopIndex") var currentLoopIndex: Int = 0
  @ConfigValue("debugWireframe") var debugWireframe = false
  @ConfigValue("wireframeMode") var wireframeMode = false

  // Settings
  @ConfigValue("volume") var volume: Double = 0.8
  @ConfigValue("resolution") var resolution: String = "1280x720"
}
