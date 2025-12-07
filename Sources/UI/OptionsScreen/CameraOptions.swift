final class CameraOptionsPanel: OptionsPanel {
  private let fieldOfViewSlider = Slider(value: 75)
  private let cameraWobblePicker = Picker(options: ["On", "Off"])

  override init() {
    super.init()

    setRows([
      Row(label: "Field of View", control: fieldOfViewSlider),
      Row(label: "Camera Wobble", control: cameraWobblePicker),
    ])
  }
}
