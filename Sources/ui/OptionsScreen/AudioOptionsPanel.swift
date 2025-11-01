import Miniaudio

final class AudioOptionsPanel: OptionsPanel {
  private let voiceVolumeSlider = Slider(value: Config.current.voiceVolume)
  private let musicVolumeSlider = Slider(value: Config.current.musicVolume)
  private let sfxVolumeSlider = Slider(value: Config.current.sfxVolume)
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

    print(try! AudioDevice.outputDevices.map { ($0.id, $0.name, $0.isDefault) })

    voiceVolumeSlider.onValueChanged = { value in
      Config.current.voiceVolume = value
    }

    musicVolumeSlider.onValueChanged = { value in
      Config.current.musicVolume = value
    }

    sfxVolumeSlider.onValueChanged = { value in
      Config.current.sfxVolume = value
    }

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
