import Miniaudio

final class AudioOptionsPanel: OptionsPanel {
  private let voiceVolumeSlider = Slider(value: Config.current.voiceVolume)
  private let musicVolumeSlider = Slider(value: Config.current.musicVolume)
  private let sfxVolumeSlider = Slider(value: Config.current.sfxVolume)
  private let uiVolumeSlider = Slider(value: Config.current.uiVolume)

  private var outputDevices: [AudioDevice] = []
  private let outputDevicePicker: Picker

  override init() {
    // Initialize picker with placeholder - will be updated with actual devices
    outputDevicePicker = Picker(options: ["Loading..."])

    super.init()

    // Load output devices
    do {
      outputDevices = try AudioDevice.outputDevices
      let deviceNames = ["System Default"] + outputDevices.map { $0.name }
      outputDevicePicker.options = deviceNames

      // Find default device index
      if let defaultIndex = outputDevices.firstIndex(where: { $0.isDefault }) {
        outputDevicePicker.selectedIndex = defaultIndex + 1  // +1 for "System Default"
      } else {
        outputDevicePicker.selectedIndex = 0  // Default to "System Default"
      }
    } catch {
      logger.error("Failed to load audio devices: \(error)")
      outputDevicePicker.options = ["System Default"]
      outputDevicePicker.selectedIndex = 0
    }

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

    outputDevicePicker.onSelectionChanged = { [weak self] index in
      guard let self = self else { return }
      do {
        if index == 0 {
          // System Default
          try AudioEngine.shared.setOutputDevice(nil)
        } else {
          // Specific device (index - 1 because index 0 is "System Default")
          let deviceIndex = index - 1
          if deviceIndex < outputDevices.count {
            try AudioEngine.shared.setOutputDevice(outputDevices[deviceIndex])
          }
        }
      } catch {
        logger.error("Failed to set output device: \(error)")
      }
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
