@MainActor
final class Config {
  static let current = Config()

  // Debug
  @ConfigValue var editorEnabled = false
  @ConfigValue var currentLoopIndex: Int = 0
  @ConfigValue var debugWireframe = false
  @ConfigValue var wireframeMode = false

  // Settings
  @ConfigValue(group: "audio") var uiVolume: Float = 1.0
  @ConfigValue(group: "audio") var voiceVolume: Float = 0.7
  @ConfigValue(group: "audio") var musicVolume: Float = 0.65
  @ConfigValue(group: "audio") var sfxVolume: Float = 0.75

  @ConfigValue(group: "display") var resolution: String = "1280x720"
  @ConfigValue(group: "display") var accentColor: Color = .rose900
  @ConfigValue(group: "display") var centeredLayout: Bool = false

  @ConfigValue(group: "language") var displayLocaleIdentifier: String = "en"
  @ConfigValue(group: "language") var voiceLocaleIdentifier: String = "en"
  @ConfigValue(group: "language") var subtitlesEnabled: Bool = true

  // Helper methods to get bindings for properties with type annotations
  // Note: Can't use $ prefix (reserved for property wrappers), so using binding prefix
  var bindingDisplayLocaleIdentifier: ConfigBinding<String> {
    ConfigBinding(
      get: { self.displayLocaleIdentifier },
      set: { self.displayLocaleIdentifier = $0 }
    )
  }

  var bindingVoiceLocaleIdentifier: ConfigBinding<String> {
    ConfigBinding(
      get: { self.voiceLocaleIdentifier },
      set: { self.voiceLocaleIdentifier = $0 }
    )
  }
}
