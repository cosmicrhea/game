@Editable final class UIDemo: RenderLoop {
  @Editor var autohideScrollbars: Bool = true
  @Editor var showColorPicker: Bool = true
  @Editor var showSliderValues: Bool = false

  private let indicator = ProgressIndicator()
  private let textField = TextField(frame: Rect(x: 20, y: 90, width: 360, height: 36), text: "Hello")
  private let textFieldWithPlaceholder = TextField(frame: Rect(x: 20, y: 140, width: 360, height: 36), text: "")
  private let textFieldWithoutBezel = TextField(frame: Rect(x: 20, y: 190, width: 360, height: 36), text: "No bezel")

  // Sliders
  private let slider: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 360, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.35, tickCount: 0)
    s.showsValueLabel = true
    return s
  }()
  private let sliderWithTickmarks: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 410, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.5, tickCount: 11)
    s.showsValueLabel = true
    return s
  }()
  private let pillSlider: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 460, width: 420, height: 36), minimumValue: 0, maximumValue: 1, value: 0.65, tickCount: 0)
    s.style = .pill
    s.showsValueLabel = true
    return s
  }()

  private let inspectorSlider: Slider = {
    let s = Slider(
      frame: Rect(x: 20, y: 560, width: 420, height: 36), maximumValue: 16, value: 0.0, tickCount: 0)
    s.style = .inspector
    s.neutralValue = 0
    s.valueLabelStyle = TextStyle.itemDescription.withMonospacedDigits(true)
    return s
  }()

  // Switch demo
  private let switchControl: Switch = {
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

  private let focusDemoRing = FocusRing()
  private var focusRingDemoRect: Rect = .zero
  private var progressIndicatorRect: Rect = .zero

  // Color controls
  private lazy var colorPicker: ColorPicker = {
    let p = ColorPicker(frame: Rect(x: 0, y: 0, width: 180, height: 180), color: Color.accent)
    p.onColorChanged = { [weak self] newColor in
      Color.accent = newColor
    }
    return p
  }()

  // Swatch picker
  private lazy var swatchPicker: SwatchPicker = {
    let g = SwatchPicker(frame: Rect(x: 20, y: 20, width: 240, height: 44))
    return g
  }()

  init() {}

  func update(deltaTime: Float) {
    indicator.update(deltaTime: deltaTime)
    switchControl.update(deltaTime: deltaTime)
    scrollView.update(deltaTime: deltaTime)
    // Sync editable toggles to the scroll view each frame
    scrollView.autohideScrollbars = autohideScrollbars
    // Sync slider value label visibility (inspector slider always shows its value)
    slider.showsValueLabel = showSliderValues
    sliderWithTickmarks.showsValueLabel = showSliderValues
    pillSlider.showsValueLabel = showSliderValues

    // If inspector slider is editing inline, its TextField draws in draw(); no per-frame update needed
  }

  func draw() {
    // UI background
    GraphicsContext.current?.renderer.setClearColor(Color(0.08, 0.08, 0.1, 1))

    let labelStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 14, color: .gray400)
    let titleStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 17, color: .gray200)
    let viewportSize = Engine.viewportSize
    let screenWidth = viewportSize.width
    let screenHeight = viewportSize.height

    let horizontalMargin: Float = 20
    let columns = 3
    let columnSpacing: Float = 28
    let verticalSpacing: Float = 36
    let availableWidth = screenWidth - horizontalMargin * 2
    let columnWidth = (availableWidth - columnSpacing * Float(columns - 1)) / Float(columns)
    var layout = MasonryLayout(
      origin: Point(horizontalMargin, screenHeight - 40),
      columns: columns,
      columnWidth: columnWidth,
      columnSpacing: columnSpacing,
      verticalSpacing: verticalSpacing
    )

    let textFieldRows: [ControlRow] = [
      ControlRow(
        title: "Basic",
        height: { self.textField.frame.size.height },
        layout: { frame in self.textField.frame = frame },
        draw: {
          self.textField.draw()
          self.drawWireframeIfEnabled(around: self.textField.frame)
        }
      ),
      ControlRow(
        title: "With Placeholder",
        height: { self.textFieldWithPlaceholder.frame.size.height },
        prepare: {
          self.textFieldWithPlaceholder.placeholder = "Search…"
          self.textFieldWithPlaceholder.leftIcon = Image("UI/Icons/phosphor-icons/magnifying-glass-bold.svg")
          self.textFieldWithPlaceholder.leftIconTint = .gray400
        },
        layout: { frame in self.textFieldWithPlaceholder.frame = frame },
        draw: {
          self.textFieldWithPlaceholder.draw()
          self.drawWireframeIfEnabled(around: self.textFieldWithPlaceholder.frame)
        }
      ),
      ControlRow(
        title: "No Bezel",
        height: { self.textFieldWithoutBezel.frame.size.height },
        prepare: { self.textFieldWithoutBezel.bezeled = false },
        layout: { frame in self.textFieldWithoutBezel.frame = frame },
        draw: {
          self.textFieldWithoutBezel.draw()
          self.drawWireframeIfEnabled(around: self.textFieldWithoutBezel.frame)
        }
      ),
    ]

    let sliderRows: [ControlRow] = [
      ControlRow(
        title: "Default Style",
        height: { self.slider.frame.size.height },
        layout: { frame in self.slider.frame = frame },
        draw: {
          self.slider.draw()
          self.drawWireframeIfEnabled(around: self.slider.frame)
        }
      ),
      ControlRow(
        title: "With Tickmarks",
        height: { self.sliderWithTickmarks.frame.size.height },
        layout: { frame in self.sliderWithTickmarks.frame = frame },
        draw: {
          self.sliderWithTickmarks.draw()
          self.drawWireframeIfEnabled(around: self.sliderWithTickmarks.frame)
        }
      ),
      ControlRow(
        title: "Pill Style",
        height: { self.pillSlider.frame.size.height },
        layout: { frame in self.pillSlider.frame = frame },
        draw: {
          self.pillSlider.draw()
          self.drawWireframeIfEnabled(around: self.pillSlider.frame)
        }
      ),
      ControlRow(
        title: "Inspector Style",
        height: { self.inspectorSlider.frame.size.height },
        layout: { frame in self.inspectorSlider.frame = frame },
        draw: {
          self.inspectorSlider.draw()
          self.drawWireframeIfEnabled(around: self.inspectorSlider.frame)
        }
      ),
    ]

    let accentHeight = swatchPicker.intrinsicSize().height
    let otherRows: [ControlRow] = [
      ControlRow(
        title: "Switch",
        height: { self.switchControl.frame.size.height },
        layout: { frame in
          let width: Float = 64
          self.switchControl.frame = Rect(x: frame.origin.x, y: frame.origin.y, width: width, height: frame.size.height)
        },
        draw: {
          self.switchControl.draw()
          self.drawWireframeIfEnabled(around: self.switchControl.frame)
        }
      )
    ]

    let scrollDemoHeight: Float = 240
    let scrollRows: [ControlRow] = [
      ControlRow(
        height: { scrollDemoHeight },
        layout: { frame in
          self.scrollView.frame = Rect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: scrollDemoHeight
          )
          self.scrollView.contentSize = Size(frame.size.width, self.scrollView.contentSize.height)
        },
        draw: {
          self.scrollView.draw()
          self.drawWireframeIfEnabled(around: self.scrollView.frame)
        }
      )
    ]

    let colorPickerSize = Size(ColorWell.defaultSize.width, ColorWell.defaultSize.height)
    var colorRows: [ControlRow] = [
      ControlRow(
        title: "Swatch Picker",
        height: { accentHeight },
        layout: { frame in
          self.swatchPicker.frame = Rect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: accentHeight
          )
        },
        draw: {
          self.swatchPicker.draw()
          self.drawWireframeIfEnabled(around: self.swatchPicker.frame)
        }
      )
    ]
    if showColorPicker {
      colorRows.append(
        ControlRow(
          title: "Color Picker",
          height: { colorPickerSize.height },
          layout: { frame in
            self.colorPicker.frame = Rect(origin: frame.origin, size: colorPickerSize)
          },
          draw: {
            self.colorPicker.draw()
            self.drawWireframeIfEnabled(around: self.colorPicker.frame)
          }
        )
      )
    }

    let systemRows: [ControlRow] = [
      ControlRow(
        title: "Progress Indicator",
        height: { 72 },
        layout: { frame in
          self.progressIndicatorRect = frame.insetBy(dx: 24, dy: 14)
        },
        draw: {
          self.indicator.draw(in: self.progressIndicatorRect)
          if Config.current.wireframeMode {
            self.progressIndicatorRect.frame(with: .magenta, lineWidth: 1)
          }
        }
      ),
      ControlRow(
        title: "Focus Ring",
        height: { 120 },
        layout: { frame in
          self.focusRingDemoRect = frame.insetBy(dx: 20, dy: 16)
        },
        draw: {
          self.focusDemoRing.draw(around: self.focusRingDemoRect, intensity: 1.0, padding: 14)
          if Config.current.wireframeMode {
            self.focusRingDemoRect.frame(with: .magenta, lineWidth: 1)
          }
        }
      ),
    ]

    func renderGroup(_ title: String, rows: [ControlRow], span: Int = 1) {
      let cardHeight = controlGroupCardHeight(for: rows)
      let totalHeight = controlGroupTotalHeight(forCardHeight: cardHeight)
      let frame = layout.place(height: totalHeight, span: span)
      drawControlGroup(
        title: title,
        frame: frame,
        rows: rows,
        titleStyle: titleStyle,
        labelStyle: labelStyle
      )
    }

    renderGroup("Sliders", rows: sliderRows)
    renderGroup("Text Fields", rows: textFieldRows)
    renderGroup("Color Controls", rows: colorRows)
    renderGroup("Other Controls", rows: otherRows)
    renderGroup("Scroll View", rows: scrollRows)
    renderGroup("Indicators", rows: systemRows)
  }

  // MARK: - Input

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    // Forward navigation/editing keys to the focused field
    // Text input is now handled via GLFW's textInputHandler, so we don't need mapKeyToCharacter anymore
    if textField.isFocused {
      if textField.handleKey(key, mods: mods) { return }
    } else if textFieldWithPlaceholder.isFocused {
      if textFieldWithPlaceholder.handleKey(key, mods: mods) { return }
    } else if textFieldWithoutBezel.isFocused {
      if textFieldWithoutBezel.handleKey(key, mods: mods) { return }
    } else if slider.isFocused {
      if slider.handleKey(key) { return }
    } else if sliderWithTickmarks.isFocused {
      if sliderWithTickmarks.handleKey(key) { return }
    } else if pillSlider.isFocused {
      if pillSlider.handleKey(key) { return }
    } else if inspectorSlider.isFocused {
      if inspectorSlider.handleKey(key) { return }
    } else if switchControl.isFocused {
      if switchControl.handleKey(key) { return }
    } else if swatchPicker.isFocused {
      if swatchPicker.handleKey(key) { return }
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    let p = mousePoint(window)
    // Manage focus and dispatch mouse down to whichever is hit
    for field in [textField, textFieldWithPlaceholder, textFieldWithoutBezel] {
      field.isFocused = false
    }
    for slider in [slider, sliderWithTickmarks, pillSlider, inspectorSlider] {
      slider.isFocused = false
    }
    switchControl.isFocused = false
    colorPicker.isFocused = false
    swatchPicker.isFocused = false
    for field in [textFieldWithoutBezel, textFieldWithPlaceholder, textField] {  // top-most first if overlapping
      if field.frame.contains(p) {
        field.isFocused = true
        _ = field.handleMouseDown(at: p)
        break
      }
    }
    for slider in [inspectorSlider, pillSlider, sliderWithTickmarks, slider] {  // top-most first if overlapping
      if slider.frame.contains(p) {
        slider.isFocused = true
        _ = slider.handleMouseDown(at: p)
        break
      }
    }
    if switchControl.frame.contains(p) {
      switchControl.isFocused = true
      _ = switchControl.handleMouseDown(at: p)
    }

    // Color controls (test after other controls but before scroll view)
    if colorPicker.interactiveBounds.contains(p) {
      colorPicker.isFocused = true
      _ = colorPicker.handleMouseDown(at: p)
      return
    }

    if swatchPicker.frame.contains(p) {
      swatchPicker.isFocused = true
      _ = swatchPicker.handleMouseDown(at: p)
      return
    }

    _ = scrollView.handleMouseDown(at: p)
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    let p = mousePoint(window)
    for field in [textField, textFieldWithPlaceholder, textFieldWithoutBezel] { field.handleMouseMove(at: p) }
    for slider in [slider, sliderWithTickmarks, pillSlider, inspectorSlider] { slider.handleMouseMove(at: p) }
    switchControl.handleMouseMove(at: p)
    scrollView.handleMouseMove(at: p)
    colorPicker.handleMouseMove(at: p)
    swatchPicker.handleMouseMove(at: p)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    for field in [textField, textFieldWithPlaceholder, textFieldWithoutBezel] { field.handleMouseUp() }
    for slider in [slider, sliderWithTickmarks, pillSlider, inspectorSlider] { slider.handleMouseUp() }
    switchControl.handleMouseUp()
    scrollView.handleMouseUp()
    colorPicker.handleMouseUp()
    swatchPicker.handleMouseUp()
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

  private struct MasonryLayout {
    let origin: Point
    let columns: Int
    let columnWidth: Float
    let columnSpacing: Float
    let verticalSpacing: Float

    private var columnHeights: [Float]

    init(origin: Point, columns: Int, columnWidth: Float, columnSpacing: Float, verticalSpacing: Float) {
      self.origin = origin
      self.columns = max(1, columns)
      self.columnWidth = columnWidth
      self.columnSpacing = columnSpacing
      self.verticalSpacing = verticalSpacing
      self.columnHeights = Array(repeating: 0, count: max(1, columns))
    }

    mutating func place(height: Float, span requestedSpan: Int) -> Rect {
      let span = max(1, min(requestedSpan, columns))
      if span == columns {
        return placeAcrossAllColumns(height: height)
      } else if span == 1 {
        return placeSingleColumn(height: height)
      } else {
        return placeMultiColumn(height: height, span: span)
      }
    }

    private mutating func placeSingleColumn(height: Float) -> Rect {
      guard let minIndex = columnHeights.enumerated().min(by: { $0.element < $1.element })?.offset else {
        return .zero
      }
      let x = origin.x + Float(minIndex) * (columnWidth + columnSpacing)
      let yTop = origin.y - columnHeights[minIndex]
      let rect = Rect(x: x, y: yTop - height, width: columnWidth, height: height)
      columnHeights[minIndex] += height + verticalSpacing
      return rect
    }

    private mutating func placeMultiColumn(height: Float, span: Int) -> Rect {
      var bestRangeStart = 0
      var bestHeight = Float.greatestFiniteMagnitude
      if columns == span {
        return placeAcrossAllColumns(height: height)
      }
      for start in 0...(columns - span) {
        let segmentHeight = columnHeights[start..<(start + span)].max() ?? 0
        if segmentHeight < bestHeight {
          bestHeight = segmentHeight
          bestRangeStart = start
        }
      }

      let x = origin.x + Float(bestRangeStart) * (columnWidth + columnSpacing)
      let yTop = origin.y - bestHeight
      let rect = Rect(
        x: x,
        y: yTop - height,
        width: totalWidth(for: span),
        height: height
      )
      let updatedHeight = bestHeight + height + verticalSpacing
      for i in bestRangeStart..<(bestRangeStart + span) {
        columnHeights[i] = updatedHeight
      }
      return rect
    }

    private mutating func placeAcrossAllColumns(height: Float) -> Rect {
      let maxHeight = columnHeights.max() ?? 0
      let yTop = origin.y - maxHeight
      let rect = Rect(
        x: origin.x,
        y: yTop - height,
        width: totalWidth(for: columns),
        height: height
      )
      let updatedHeight = maxHeight + height + verticalSpacing
      columnHeights = Array(repeating: updatedHeight, count: columns)
      return rect
    }

    private func totalWidth(for span: Int) -> Float {
      let spanFloat = Float(span)
      return spanFloat * columnWidth + Float(span - 1) * columnSpacing
    }
  }

  private struct ControlRow {
    let title: String?
    let heightProvider: () -> Float
    let prepare: (() -> Void)?
    let layoutControl: (Rect) -> Void
    let drawControl: () -> Void
    let spacingAfter: Float?

    init(
      title: String? = nil,
      height: @escaping () -> Float,
      prepare: (() -> Void)? = nil,
      layout: @escaping (Rect) -> Void,
      draw: @escaping () -> Void,
      spacingAfter: Float? = nil
    ) {
      self.title = title
      self.heightProvider = height
      self.prepare = prepare
      self.layoutControl = layout
      self.drawControl = draw
      self.spacingAfter = spacingAfter
    }

    func height() -> Float { heightProvider() }
    func prepareIfNeeded() { prepare?() }
    func layout(_ rect: Rect) { layoutControl(rect) }
    func draw() { drawControl() }
  }

  private enum ControlGroupMetrics {
    static let cornerRadius: Float = 18
    static let titleAreaHeight: Float = 32
    static let titleBaselineOffset: Float = 10
    static let contentPadding: Float = 18
    static let labelSpacingTop: Float = 10
    static let labelSpacingBottom: Float = 2
    static let rowSpacing: Float = 20
  }

  private func controlGroupCardHeight(for rows: [ControlRow]) -> Float {
    var height = ControlGroupMetrics.contentPadding
    for (index, row) in rows.enumerated() {
      if row.title != nil {
        height += ControlGroupMetrics.labelSpacingTop + ControlGroupMetrics.labelSpacingBottom
      }
      height += row.height()
      if index < rows.count - 1 {
        height += row.spacingAfter ?? ControlGroupMetrics.rowSpacing
      }
    }
    height += ControlGroupMetrics.contentPadding
    return height
  }

  private func controlGroupTotalHeight(forCardHeight cardHeight: Float) -> Float {
    cardHeight + ControlGroupMetrics.titleAreaHeight
  }

  private func drawControlGroup(
    title: String,
    frame: Rect,
    rows: [ControlRow],
    titleStyle: TextStyle,
    labelStyle: TextStyle
  ) {
    guard frame.size.height > ControlGroupMetrics.titleAreaHeight else { return }
    let cardRect = Rect(
      x: frame.origin.x,
      y: frame.origin.y,
      width: frame.size.width,
      height: frame.size.height - ControlGroupMetrics.titleAreaHeight
    )

    let contentX = cardRect.origin.x + ControlGroupMetrics.contentPadding
    let contentWidth = cardRect.size.width - ControlGroupMetrics.contentPadding * 2
    var cursorY = cardRect.maxY - ControlGroupMetrics.contentPadding

    let backgroundColor = Color.gray700.withAlphaComponent(0.32)
    RoundedRect(cardRect, cornerRadius: ControlGroupMetrics.cornerRadius).draw(color: backgroundColor)
    RoundedRect(cardRect, cornerRadius: ControlGroupMetrics.cornerRadius)
      .stroke(color: Color.white.withAlphaComponent(0.08), lineWidth: 1)

    title.draw(
      at: Point(contentX, cardRect.maxY + ControlGroupMetrics.titleBaselineOffset),
      style: titleStyle,
      anchor: .bottomLeft
    )

    for (index, row) in rows.enumerated() {
      row.prepareIfNeeded()

      if let rowTitle = row.title {
        cursorY -= ControlGroupMetrics.labelSpacingTop
        let labelPoint = Point(contentX, cursorY)
        rowTitle.draw(at: labelPoint, style: labelStyle, anchor: .bottomLeft)
        cursorY -= ControlGroupMetrics.labelSpacingBottom
      }

      let controlHeight = row.height()
      cursorY -= controlHeight

      let controlRect = Rect(x: contentX, y: cursorY, width: contentWidth, height: controlHeight)
      row.layout(controlRect)
      row.draw()

      if index < rows.count - 1 {
        cursorY -= row.spacingAfter ?? ControlGroupMetrics.rowSpacing
      }
    }
  }

  private func drawWireframeIfEnabled(around rect: Rect) {
    if Config.current.wireframeMode {
      rect.frame(with: .magenta, lineWidth: 1)
    }
  }

  private func mousePoint(_ window: Window) -> Point {
    Point(Float(window.mouse.position.x), Float(Engine.viewportSize.height) - Float(window.mouse.position.y))
  }
}
