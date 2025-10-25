@Editor final class UIDemo: RenderLoop {
  @Editable var autohideScrollbars: Bool = true

  private let indicator = ProgressIndicator()
  private let tfBasic = TextField(frame: Rect(x: 20, y: 90, width: 360, height: 36), text: "Hello")
  private let tfPlaceholder = TextField(frame: Rect(x: 20, y: 140, width: 360, height: 36), text: "")
  private let tfMultiline = TextField(
    frame: Rect(x: 20, y: 190, width: 480, height: 90), text: "This is a\nmultiline\nfield.", singleLine: false)
  private let tfNoBorder = TextField(frame: Rect(x: 20, y: 300, width: 360, height: 36), text: "No bezel")

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

    "Multiline".draw(
      at: Point(tfMultiline.frame.origin.x, tfMultiline.frame.maxY + 6), style: labelStyle,
      anchor: .bottomLeft)
    tfMultiline.draw()

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
    let screenH2 = Float(Engine.viewportSize.height)
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
    // Cmd+A: Select all for focused field
    if mods.contains(.command) && key == .a {
      for field in [tfBasic, tfPlaceholder, tfMultiline, tfNoBorder] where field.isFocused {
        // Simulate select-all by clicking at start then dragging to end
        let originX = field.frame.origin.x + field.contentInsets.left
        let baselineY: Float =
          field.text.isEmpty
          ? field.frame.midY : (field.frame.origin.y + field.contentInsets.top + field.textStyle.fontSize)
        let endIndex = field.text.unicodeScalars.count
        _ = field.handleMouseDown(at: Point(originX, baselineY))
        let endX = originX + (Float(endIndex) * 8)
        field.handleMouseMove(at: Point(endX, baselineY))
        field.handleMouseUp()
        return
      }
    }

    // Forward navigation/editing keys to the focused field
    if tfBasic.isFocused {
      if tfBasic.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfBasic.insertText(s)
        return
      }
    } else if tfPlaceholder.isFocused {
      if tfPlaceholder.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfPlaceholder.insertText(s)
        return
      }
    } else if tfMultiline.isFocused {
      if tfMultiline.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfMultiline.insertText(s)
        return
      }
    } else if tfNoBorder.isFocused {
      if tfNoBorder.handleKey(key) { return }
      if let s = mapKeyToCharacter(key, mods: mods) {
        _ = tfNoBorder.insertText(s)
        return
      }
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
    for field in [tfBasic, tfPlaceholder, tfMultiline, tfNoBorder] {
      field.isFocused = false
    }
    for slider in [slStandard, slTicks, slPill, slInspector] {
      slider.isFocused = false
    }
    swMain.isFocused = false
    colorPicker.isFocused = false
    colorWell.isFocused = false
    accentSelector.isFocused = false
    for field in [tfNoBorder, tfMultiline, tfPlaceholder, tfBasic] {  // top-most first if overlapping
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
    for field in [tfBasic, tfPlaceholder, tfMultiline, tfNoBorder] { field.handleMouseMove(at: p) }
    for slider in [slStandard, slTicks, slPill, slInspector] { slider.handleMouseMove(at: p) }
    swMain.handleMouseMove(at: p)
    scrollView.handleMouseMove(at: p)
    colorPicker.handleMouseMove(at: p)
    colorWell.handleMouseMove(at: p)
    accentSelector.handleMouseMove(at: p)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    for field in [tfBasic, tfPlaceholder, tfMultiline, tfNoBorder] { field.handleMouseUp() }
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

  // MARK: - Helpers

  private func mousePoint(_ window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }

  private func mapKeyToCharacter(_ key: Keyboard.Key, mods: Keyboard.Modifier) -> String? {
    let shifted = mods.contains(.shift)
    switch key {
    case .space: return " "
    case .apostrophe: return shifted ? "\"" : "'"
    case .comma: return shifted ? "<" : ","
    case .period: return shifted ? ">" : "."
    case .slash: return shifted ? "?" : "/"
    case .minus: return shifted ? "_" : "-"
    case .equal: return shifted ? "+" : "="
    case .semicolon: return shifted ? ":" : ";"
    case .num0: return shifted ? ")" : "0"
    case .num1: return shifted ? "!" : "1"
    case .num2: return shifted ? "@" : "2"
    case .num3: return shifted ? "#" : "3"
    case .num4: return shifted ? "$" : "4"
    case .num5: return shifted ? "%" : "5"
    case .num6: return shifted ? "^" : "6"
    case .num7: return shifted ? "&" : "7"
    case .num8: return shifted ? "*" : "8"
    case .num9: return shifted ? "(" : "9"
    case .a: return shifted ? "A" : "a"
    case .b: return shifted ? "B" : "b"
    case .c: return shifted ? "C" : "c"
    case .d: return shifted ? "D" : "d"
    case .e: return shifted ? "E" : "e"
    case .f: return shifted ? "F" : "f"
    case .g: return shifted ? "G" : "g"
    case .h: return shifted ? "H" : "h"
    case .i: return shifted ? "I" : "i"
    case .j: return shifted ? "J" : "j"
    case .k: return shifted ? "K" : "k"
    case .l: return shifted ? "L" : "l"
    case .m: return shifted ? "M" : "m"
    case .n: return shifted ? "N" : "n"
    case .o: return shifted ? "O" : "o"
    case .p: return shifted ? "P" : "p"
    case .q: return shifted ? "Q" : "q"
    case .r: return shifted ? "R" : "r"
    case .s: return shifted ? "S" : "s"
    case .t: return shifted ? "T" : "t"
    case .u: return shifted ? "U" : "u"
    case .v: return shifted ? "V" : "v"
    case .w: return shifted ? "W" : "w"
    case .x: return shifted ? "X" : "x"
    case .y: return shifted ? "Y" : "y"
    case .z: return shifted ? "Z" : "z"
    default: return nil
    }
  }
}
