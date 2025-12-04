private let voiceLanguages = [
  "en": "English",
  "da": "Danish",
]

private let displayLanguages = [
  "en": "English",
  "da": "Danish",
]

final class LanguageOptionsPanel: OptionsPanel {
  let voiceLanguagePicker = Picker(value: Config.current.bindingVoiceLocaleIdentifier, options: voiceLanguages)
  let displayLanguagePicker = Picker(value: Config.current.bindingDisplayLocaleIdentifier, options: displayLanguages)
  //let subtitlesSwitch = Switch(isOn: true)
  let subtitlesPicker = Picker(options: ["On", "Off"])

  override init() {
    super.init()

    setRows([
      Row(label: "Voice Language", control: voiceLanguagePicker),
      Row(label: "Display Language", control: displayLanguagePicker),
      //Row(label: "Subtitles", control: subtitlesSwitch),
      Row(label: "Subtitles", control: subtitlesPicker),
    ])
  }
}
