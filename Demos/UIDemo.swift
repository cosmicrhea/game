@Editor final class UIDemo: RenderLoop {
  @Editable var autohideScrollbars: Bool = true

  private let indicator = ProgressIndicator()
  private let tfBasic = TextField(frame: Rect(x: 20, y: 90, width: 360, height: 36), text: "Hello")
  private let tfPlaceholder = TextField(frame: Rect(x: 20, y: 140, width: 360, height: 36), text: "")
  private let tfNoBorder = TextField(frame: Rect(x: 20, y: 190, width: 360, height: 36), text: "No bezel")

  // Sliders
  private let slStandard: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 360, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.35, tickCount: 0)
    s.showsValueLabel = true
    return s
  }()
  private let slTicks: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 410, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.5, tickCount: 11)
    s.showsValueLabel = true
    return s
  }()
  private let slPill: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 460, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.65, tickCount: 0)
    s.style = .pill
    s.showsValueLabel = true
    return s
  }()

  private let slInspector: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 560, width: 420, height: 36), maximumValue: 16, value: 0.0, tickCount: 0)
    s.style = .inspector
    s.neutralValue = 0
    s.valueLabelStyle = TextStyle.itemDescription.withMonospacedDigits(true)
    return s
  }()

  // Switch demo
  private let swMain: Switch = {
    let s = Switch(frame: Rect(x: 20, y: 520, width: 64, height: 36), isOn: false)
    return s
  }()

  // ScrollView demo
  private let scrollView: ScrollView = {
    let sv = ScrollView(frame: Rect(x: 520, y: 90, width: 420, height: 280), contentSize: Size(420, 1200))
    sv.backgroundColor = Color.gray700.withAlphaComponent(0.22)
    sv.showsScrollbar = true
    sv.onDrawContent = { origin in
      // Draw a list of rows with alternating colors and labels
      let rowHeight: Float = 40
      let rows = 30
      let style = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray200)
      for i in 0..<rows {
        // Place Row 1 at the top by drawing from top downward
        let yTop = origin.y + sv.contentSize.height - rowHeight
        let y = yTop - Float(i) * rowHeight
        let r = Rect(x: origin.x, y: y, width: sv.frame.size.width, height: rowHeight - 1)
        let bg = (i % 2 == 0) ? Color.gray700.withAlphaComponent(0.45) : Color.gray700.withAlphaComponent(0.25)
        r.fill(with: bg)
        let label = "Row \(i + 1)"
        label.draw(at: Point(r.origin.x + 10, r.midY), style: style, anchor: .left)
      }
    }
    return sv
  }()

  // Color controls (top-right)
  private lazy var colorWell: ColorWell = {
    ColorWell(frame: Rect(x: 0, y: 0, width: 96, height: 28), color: Color.accent)
  }()
  private lazy var colorPicker: ColorPicker = {
    let p = ColorPicker(frame: Rect(x: 0, y: 0, width: 180, height: 180), color: Color.accent)
    p.onColorChanged = { [weak self] newColor in
      self?.colorWell.color = newColor
      Color.accent = newColor
    }
    return p
  }()

  // Accent selector (bottom-left)
  private lazy var accentSelector: AccentRadioGroup = {
    let g = AccentRadioGroup(frame: Rect(x: 20, y: 20, width: 240, height: 44))
    return g
  }()

  init() {}

  func update(deltaTime: Float) {
    indicator.update(deltaTime: deltaTime)
    swMain.update(deltaTime: deltaTime)
    scrollView.update(deltaTime: deltaTime)
    // Sync editable toggles to the scroll view each frame
    scrollView.autohideScrollbars = autohideScrollbars

    // If inspector slider is editing inline, its TextField draws in draw(); no per-frame update needed
  }

  func draw() {
    // UI background
    GraphicsContext.current?.renderer.setClearColor(Color(0.08, 0.08, 0.1, 1))

    // Spinner
    indicator.draw()

    // TextField demos (flipped Y; place labels just below each control's bottom)
    let labelStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400)

    "Basic".draw(
      at: Point(tfBasic.frame.origin.x, tfBasic.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    tfBasic.draw()

    "With placeholder".draw(
      at: Point(tfPlaceholder.frame.origin.x, tfPlaceholder.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    tfPlaceholder.placeholder = "Search…"
    tfPlaceholder.leftIcon = Image("UI/Icons/phosphor-icons/magnifying-glass-bold.svg")
    tfPlaceholder.leftIconTint = .gray400
    tfPlaceholder.draw()

    tfNoBorder.bezeled = false
    "No bezel".draw(
      at: Point(tfNoBorder.frame.origin.x, tfNoBorder.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    tfNoBorder.draw()

    // Slider demos
    "Slider".draw(
      at: Point(slStandard.frame.origin.x, slStandard.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    slStandard.draw()

    "Slider with tickmarks".draw(
      at: Point(slTicks.frame.origin.x, slTicks.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    slTicks.draw()

    "Slider (pill)".draw(
      at: Point(slPill.frame.origin.x, slPill.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    slPill.draw()

    "Slider (inspector)".draw(
      at: Point(slInspector.frame.origin.x, slInspector.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    slInspector.draw()

    // Switch demo
    "Switch".draw(
      at: Point(swMain.frame.origin.x, swMain.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    swMain.draw()

    // ScrollView demo anchored to the right edge, 20pt from top/right
    let svW = scrollView.frame.size.width
    let svH = scrollView.frame.size.height
    let screenW = Float(Engine.viewportSize.width)
    let screenH = Float(Engine.viewportSize.height)
    scrollView.frame = Rect(x: screenW - svW - 20, y: screenH - svH - 20, width: svW, height: svH)

    // Title
    "ScrollView".draw(
      at: Point(scrollView.frame.origin.x, scrollView.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    scrollView.draw()

    // Color Picker anchored to bottom-right
    let pickerSize: Float = 180
    let margin: Float = 20
    let screenW2 = Float(Engine.viewportSize.width)
    //let screenH2 = Float(Engine.viewportSize.height)
    colorPicker.frame = Rect(
      x: screenW2 - pickerSize - margin,
      y: margin,
      width: pickerSize,
      height: pickerSize
    )
    colorWell.frame = Rect(
      x: colorPicker.frame.origin.x,
      y: colorPicker.frame.maxY + 12,
      width: 96,
      height: 28
    )
    colorPicker.draw()
    colorWell.draw()

    // Accent selector anchored to bottom-left
    let selectorSize = accentSelector.intrinsicSize()
    accentSelector.frame = Rect(x: 20, y: 20, width: selectorSize.width, height: selectorSize.height)
    accentSelector.draw()
  }

  // MARK: - Input

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Forward navigation/editing keys to the focused field
    // Text input is now handled via GLFW's textInputHandler, so we don't need mapKeyToCharacter anymore
    if tfBasic.isFocused {
      if tfBasic.handleKey(key, mods: mods) { return }
    } else if tfPlaceholder.isFocused {
      if tfPlaceholder.handleKey(key, mods: mods) { return }
    } else if tfNoBorder.isFocused {
      if tfNoBorder.handleKey(key, mods: mods) { return }
    } else if slStandard.isFocused {
      if slStandard.handleKey(key) { return }
    } else if slTicks.isFocused {
      if slTicks.handleKey(key) { return }
    } else if slPill.isFocused {
      if slPill.handleKey(key) { return }
    } else if slInspector.isFocused {
      if slInspector.handleKey(key) { return }
    } else if swMain.isFocused {
      if swMain.handleKey(key) { return }
    } else if accentSelector.isFocused {
      if accentSelector.handleKey(key) { return }
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    let p = mousePoint(window)
    // Manage focus and dispatch mouse down to whichever is hit
    for field in [tfBasic, tfPlaceholder, tfNoBorder] {
      field.isFocused = false
    }
    for slider in [slStandard, slTicks, slPill, slInspector] {
      slider.isFocused = false
    }
    swMain.isFocused = false
    colorPicker.isFocused = false
    colorWell.isFocused = false
    accentSelector.isFocused = false
    for field in [tfNoBorder, tfPlaceholder, tfBasic] {  // top-most first if overlapping
      if field.frame.contains(p) {
        field.isFocused = true
        _ = field.handleMouseDown(at: p)
        break
      }
    }
    for slider in [slInspector, slPill, slTicks, slStandard] {  // top-most first if overlapping
      if slider.frame.contains(p) {
        slider.isFocused = true
        _ = slider.handleMouseDown(at: p)
        break
      }
    }
    if swMain.frame.contains(p) {
      swMain.isFocused = true
      _ = swMain.handleMouseDown(at: p)
    }

    // Color controls (test after other controls but before scroll view)
    if colorPicker.frame.contains(p) {
      colorPicker.isFocused = true
      _ = colorPicker.handleMouseDown(at: p)
      return
    }
    if colorWell.frame.contains(p) {
      colorWell.isFocused = true
      _ = colorWell.handleMouseDown(at: p)
      return
    }

    if accentSelector.frame.contains(p) {
      accentSelector.isFocused = true
      _ = accentSelector.handleMouseDown(at: p)
      return
    }

    _ = scrollView.handleMouseDown(at: p)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    let p = mousePoint(window)
    for field in [tfBasic, tfPlaceholder, tfNoBorder] { field.handleMouseMove(at: p) }
    for slider in [slStandard, slTicks, slPill, slInspector] { slider.handleMouseMove(at: p) }
    swMain.handleMouseMove(at: p)
    scrollView.handleMouseMove(at: p)
    colorPicker.handleMouseMove(at: p)
    colorWell.handleMouseMove(at: p)
    accentSelector.handleMouseMove(at: p)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    for field in [tfBasic, tfPlaceholder, tfNoBorder] { field.handleMouseUp() }
    for slider in [slStandard, slTicks, slPill, slInspector] { slider.handleMouseUp() }
    swMain.handleMouseUp()
    scrollView.handleMouseUp()
    colorPicker.handleMouseUp()
    colorWell.handleMouseUp()
    accentSelector.handleMouseUp()
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    let p = mousePoint(window)
    scrollView.handleScroll(xOffset: xOffset, yOffset: yOffset, mouse: p)
  }

  func onTextInput(window: Window, text: String) {
    // Route text input to the currently focused TextField
    if let focusedField = TextField.currentFocusedField {
      _ = focusedField.insertText(text)
    }
  }

  // MARK: - Helpers

  private func mousePoint(_ window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }
}
