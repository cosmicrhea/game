final class ControlsOptionsPanel: OptionsPanel {
  private let runTypePicker = Picker(options: ["Toggle", "Hold"])
  private let crouchTypePicker = Picker(options: ["Toggle", "Hold"])
  private let cursorLockPicker = Picker(options: ["On", "Off"])
  private let autoreloadPicker = Picker(options: ["On", "Off"])
  private let controllerVibrationPicker = Picker(options: ["On", "Off"])

  override init() {
    super.init()

    setRows([
      Row(label: "Run Type", control: runTypePicker),
      Row(label: "Crouch Type", control: crouchTypePicker),
      Row(label: "Cursor Lock", control: cursorLockPicker),
      Row(label: "Auto-reload", control: autoreloadPicker),
      Row(label: "Controller Vibration", control: controllerVibrationPicker),
    ])
  }
}
