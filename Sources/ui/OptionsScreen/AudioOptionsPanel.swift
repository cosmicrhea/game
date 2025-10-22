import Miniaudio

final class AudioOptionsPanel: OptionsPanel {
  private let voice = Slider(minimumValue: 0, maximumValue: 100, value: 70, tickCount: 11)
  private let music = Slider(minimumValue: 0, maximumValue: 100, value: 65, tickCount: 11)
  private let sfx = Slider(minimumValue: 0, maximumValue: 100, value: 75, tickCount: 11)
  private let ui = Slider(minimumValue: 0, maximumValue: 100, value: 80, tickCount: 11)

  private let outputPicker = Picker(
    options: [
      "System Default",
      "MacBook Pro Speakers",
      "Freya’s AirPods Max (Starlight)",
    ],
  )

  override init() {
    super.init()

    print(try! AudioDevice.outputDevices.map { ($0.id, $0.name, $0.isDefault) })

    ui.onValueChanged = { UISound.volume = $0 / 100 }

    setRows([
      Row(label: "Voice Volume", control: voice),
      Row(label: "Ambiance & Music Volume", control: music),
      Row(label: "Sound Effects Volume", control: sfx),
      Row(label: "UI Volume", control: ui),
      Row(label: "Output Device", control: outputPicker),
    ])
  }
}
