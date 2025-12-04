final class DisplayOptionsPanel: OptionsPanel {
  private let hdrModePicker = Picker(options: ["On", "Off"])
  private let colorSpacePicker = Picker(options: ["sRGB", "Display P3"] as [String])

  override init() {
    super.init()

    setRows([
      Row(label: "High Dynamic Range", control: hdrModePicker),
      Row(label: "Color Space", control: colorSpacePicker),
    ])
  }
}
