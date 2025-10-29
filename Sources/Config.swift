@MainActor
final class Config {
  static let current = Config()

  // Debug
  @ConfigValue var editorEnabled = false
  @ConfigValue var currentLoopIndex: Int = 0
  @ConfigValue var debugWireframe = false
  @ConfigValue var wireframeMode = false

  // Settings
  @ConfigValue("audio.uiVolume") var uiVolume: Float = 1.0
  @ConfigValue("audio.voiceVolume") var voiceVolume: Float = 0.7
  @ConfigValue("audio.musicVolume") var musicVolume: Float = 0.65
  @ConfigValue("audio.sfxVolume") var sfxVolume: Float = 0.75

  @ConfigValue var resolution: String = "1280x720"
  @ConfigValue var accentColor: Color = .rose900
  @ConfigValue var centeredLayout: Bool = false
}
