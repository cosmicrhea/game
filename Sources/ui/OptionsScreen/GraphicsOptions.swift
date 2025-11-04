final class GraphicsOptionsPanel: OptionsPanel {
  private let displayModePicker = Picker(options: ["Full Screen", "Windowed"])
  private let resolutionPicker = Picker(options: ["1920x1080", "1280x720", "1024x576", "800x600", "640x480"])

  override init() {
    super.init()

    setRows([
      Row(label: "Display Mode", control: displayModePicker),
      Row(label: "Resolution", control: resolutionPicker),
    ])
  }
}
