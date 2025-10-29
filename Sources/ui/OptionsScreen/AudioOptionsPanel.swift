import Miniaudio

final class AudioOptionsPanel: OptionsPanel {
  private let voiceVolumeSlider = Slider(minimumValue: 0, maximumValue: 100, value: 70, tickCount: 11)
  private let musicVolumeSlider = Slider(minimumValue: 0, maximumValue: 100, value: 65, tickCount: 11)
  private let sfxVolumeSlider = Slider(minimumValue: 0, maximumValue: 100, value: 75)
  private let uiVolumeSlider = Slider(value: Config.current.uiVolume)

  private let outputDevicePicker = Picker(
    options: [
      "System Default",
      "MacBook Pro Speakers",
      "Freya’s AirPods Max (Starlight)",
    ],
  )

  override init() {
    super.init()

    //print(try! AudioDevice.outputDevices.map { ($0.id, $0.name, $0.isDefault) })

    uiVolumeSlider.onValueChanged = { value in
      Config.current.uiVolume = value
      UISound.volume = value
    }

    setRows([
      Row(label: "Voice Volume", control: voiceVolumeSlider),
      Row(label: "Ambiance & Music Volume", control: musicVolumeSlider),
      Row(label: "Sound Effects Volume", control: sfxVolumeSlider),
      Row(label: "UI Volume", control: uiVolumeSlider),
      Row(label: "Output Device", control: outputDevicePicker),
    ])
  }
}
