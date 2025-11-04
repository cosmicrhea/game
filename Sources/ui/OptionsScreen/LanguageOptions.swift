final class LanguageOptionsPanel: OptionsPanel {
  private let voiceLanguagePicker = Picker(options: ["English", "Danish"])
  private let displayLanguagePicker = Picker(options: ["English", "Danish"])
  private let subtitlesSwitch = Switch(isOn: true)

  override init() {
    super.init()

    setRows([
      Row(label: "Voice Language", control: voiceLanguagePicker),
      Row(label: "Display Language", control: displayLanguagePicker),
      Row(label: "Subtitles", control: subtitlesSwitch),
    ])
  }
}
