import Foundation

public final class EditorPanel: OptionsPanel {
  private var editorProperties: [AnyEditorProperty] = []
  private var propertyGroups: [EditorPropertyGroup] = []
  private var editorFunctions: [EditorFunction] = []
  private var sliders: [Slider] = []
  private var switches: [Switch] = []
  private var pickers: [Picker] = []
  private var currentObject: Editing?
  private var editorWindowSize: Size = Size(520, 720)
  private var noEditorMessage: String? = nil

  public override init() {
    super.init()
    setupEditorPanel()
  }

  public override func draw() {
    if let message = noEditorMessage {
      let style = TextStyle.itemDescription.withColor(.gray300)
      let center = Point(editorWindowSize.width * 0.5, editorWindowSize.height * 0.5)
      message.draw(at: center, style: style, anchor: .center)
      return
    }
    super.draw()
  }

  // Override layout to use editor window size instead of main window size
  public override func layout() {
    let w = editorWindowSize.width
    let h = editorWindowSize.height

    // For the editor, use an edge-to-edge left-aligned panel with small side padding
    let left: Float = sidePadding
    let width = w - 2 * sidePadding
    let bottom = bottomMargin
    let height = h - bottomMargin - topMargin
    panelRect = Rect(x: left, y: bottom, width: width, height: height)

    // Rows rects: top-to-bottom visual order matching source declaration order.
    // Section headers get extra top margin, except the very first header.
    // Coordinate system is bottom-left; 'origin.y' is the bottom of each row.
    let extraHeaderTopMargin: Float = 20

    // Compute per-row heights (variable): section headers are taller if not first row
    let rowHeights: [Float] = rows.enumerated().map { (i, row) in
      if row.control is SectionHeader, i != 0 {
        return rowHeight + extraHeaderTopMargin
      } else {
        return rowHeight
      }
    }

    // Build rects top-to-bottom: row 0 sits at the top. For each row, place its bottom at
    // maxY - accumulatedHeightSoFar - thisRowHeight.
    var accumulated: Float = 0
    rowRects = rowHeights.enumerated().map { (i, h) in
      let bottomY = panelRect.maxY - accumulated - h
      accumulated += h
      return Rect(x: panelRect.origin.x, y: bottomY, width: panelRect.size.width, height: h)
    }

    for (i, r) in rowRects.enumerated() where rows.indices.contains(i) {
      if rows[i].control is SectionHeader {
        rows[i].control.frame = Rect(x: r.origin.x, y: r.origin.y, width: r.size.width, height: r.size.height)
        continue
      }

      let isSlider = rows[i].control is Slider
      let isSwitch = rows[i].control is Switch
      let isPicker = rows[i].control is Picker

      // Size by control type
      let controlWidth: Float
      let controlHeight: Float
      let rightReserve: Float = isSlider ? 32 : 0  // leave space for slider value label
      if isSlider {
        controlWidth = r.size.width * 0.55
        controlHeight = 36
      } else if isSwitch {
        controlWidth = 68
        controlHeight = 28
      } else if isPicker {
        controlWidth = r.size.width * 0.55
        controlHeight = 36
      } else {
        controlWidth = r.size.width * 0.55
        controlHeight = 36
      }

      // Slightly reduce right padding for switches to visually align with panel edge
      let rightPadding = isSwitch ? max(0, sidePadding - 6) : sidePadding
      let x = r.origin.x + r.size.width - rightReserve - rightPadding - controlWidth
      let y = r.origin.y + (r.size.height - controlHeight) * 0.5
      rows[i].control.frame = Rect(x: x, y: y, width: controlWidth, height: controlHeight)
    }
  }

  /// Update the panel to show properties for a given Editing object
  public func updateForObject(_ object: Editing) {
    noEditorMessage = nil
    currentObject = object
    let properties = object.getEditableProperties()

    // Extract functions separately
    editorFunctions = properties.compactMap { $0 as? EditorFunction }

    // Check if we have grouped properties
    if properties.first is EditorPropertyGroup {
      propertyGroups = properties.compactMap { $0 as? EditorPropertyGroup }
      editorProperties = []
    } else {
      editorProperties = properties.compactMap { $0 as? AnyEditorProperty }
      propertyGroups = []
    }

    generateControls()
  }

  /// Show a fallback message for non-editable objects
  public func showNoEditorMessage() {
    currentObject = nil
    editorProperties = []
    propertyGroups = []
    sliders.removeAll()
    noEditorMessage = "No Editor"
    setRows([])
  }

  /// Update the editor window size for proper layout
  public func updateWindowSize(_ size: Size) {
    editorWindowSize = size
  }

  private func setupEditorPanel() {
    // Configure panel for editor use
    sidePadding = 20
    topMargin = 32
    bottomMargin = 32
    rowHeight = 32
    rightPaneRatio = 1
    labelStyle = TextStyle.itemDescription
  }

  /// Advance animations and time-based UI for editor controls
  public override func update(deltaTime: Float) {
    for sw in switches { sw.update(deltaTime: deltaTime) }
  }

  /// Decorative section header control that draws a title line
  private final class SectionHeader: OptionsControl {
    var frame: Rect = .zero
    var isFocused: Bool = false
    var isFocusable: Bool { false }
    private let title: String
    private let titleStyle: TextStyle
    init(title: String) {
      self.title = title
      // Use item name style for section headers
      self.titleStyle = TextStyle.itemName
    }
    func draw() {
      // Bottom-align the title so extra height adds margin above the header
      title.draw(at: Point(frame.origin.x, frame.origin.y + 8), style: titleStyle, anchor: .bottomLeft)
      // Thin separator line across near the bottom
      let lineY = frame.origin.y + 6
      let lineRect = Rect(x: frame.origin.x, y: lineY, width: frame.size.width, height: 1)
      lineRect.fill(with: Color(1, 1, 1, 0.05))
    }
    func handleKey(_ key: Keyboard.Key) -> Bool { return false }
    func handleMouseDown(at position: Point) -> Bool { return false }
    func handleMouseMove(at position: Point) {}
    func handleMouseUp() {}
  }

  private func generateControls() {
    sliders.removeAll()
    switches.removeAll()
    pickers.removeAll()
    var rows: [Row] = []

    if !propertyGroups.isEmpty {
      // Handle grouped properties with section headers
      for group in propertyGroups {
        // Section header row
        let headerControl = SectionHeader(title: group.name)
        rows.append(Row(label: "", control: headerControl))
        for property in group.properties {
          if let slider = createSliderForProperty(property) {
            sliders.append(slider)
            rows.append(Row(label: property.displayName, control: slider))
          } else if let sw = createSwitchForProperty(property) {
            switches.append(sw)
            rows.append(Row(label: property.displayName, control: sw))
          } else if let picker = createPickerForProperty(property) {
            pickers.append(picker)
            rows.append(Row(label: property.displayName, control: picker))
          }
        }
      }
    } else {
      // Handle ungrouped properties
      for property in editorProperties {
        if let slider = createSliderForProperty(property) {
          sliders.append(slider)
          rows.append(Row(label: property.displayName, control: slider))
        } else if let sw = createSwitchForProperty(property) {
          switches.append(sw)
          rows.append(Row(label: property.displayName, control: sw))
        } else if let picker = createPickerForProperty(property) {
          pickers.append(picker)
          rows.append(Row(label: property.displayName, control: picker))
        }
      }
    }

    // Add function buttons at the end
    for editorFunction in editorFunctions {
      rows.append(Row(button: editorFunction.displayName, action: editorFunction.action))
    }

    setRows(rows)
  }

  private func createSliderForProperty(_ property: AnyEditorProperty) -> Slider? {
    // Only create sliders for Float properties with valid ranges
    guard let range = property.validRange,
      let floatValue = property.value as? Float
    else {
      return nil
    }

    // Use smooth sliders in the editor for continuous control
    let slider = Slider(
      minimumValue: Float(range.lowerBound),
      maximumValue: Float(range.upperBound),
      value: floatValue,
      continuous: true
    )

    // Show value label with two decimals
    slider.showsValueLabel = true
    slider.valueFormatter = { v in String(format: "%.2f", v) }

    // Set up the value change callback to update the property
    slider.onValueChanged = { newValue in
      // Update the property value
      property.setValue(Float(newValue))
    }

    return slider
  }

  private func createSwitchForProperty(_ property: AnyEditorProperty) -> Switch? {
    guard property.validRange == nil, let boolValue = property.value as? Bool else { return nil }
    let sw = Switch(frame: .zero, isOn: boolValue)
    sw.onToggle = { newValue in
      property.setValue(newValue)
    }
    return sw
  }

  private func createPickerForProperty(_ property: AnyEditorProperty) -> Picker? {
    // Check if this is a String property
    guard let stringValue = property.value as? String else { return nil }

    // Try to get static options from @Editor if available
    var availableOptions: [String] = [stringValue]  // Default to current value
    if let staticOptions = property.pickerOptions, !staticOptions.isEmpty {
      availableOptions = staticOptions
    }

    // Ensure current value is in the options
    if !availableOptions.contains(stringValue) {
      availableOptions.insert(stringValue, at: 0)
    }

    let picker = Picker(
      frame: .zero, options: availableOptions, selectedIndex: availableOptions.firstIndex(of: stringValue) ?? 0)
    picker.onSelectionChanged = { newIndex in
      if newIndex < picker.options.count {
        property.setValue(picker.options[newIndex])
      }
    }
    return picker
  }

  /// Update slider values when the underlying object properties change
  public func refreshValues() {
    guard let object = currentObject else { return }

    let properties = object.getEditableProperties()
    let currentProperties: [AnyEditorProperty]

    if properties.first is EditorPropertyGroup {
      currentProperties = propertyGroups.flatMap { $0.properties }
    } else {
      currentProperties = editorProperties
    }

    var sliderIndex = 0
    var switchIndex = 0
    var pickerIndex = 0
    for property in currentProperties {
      if let floatValue = property.value as? Float, sliderIndex < sliders.count {
        sliders[sliderIndex].value = floatValue
        sliderIndex += 1
      } else if let boolValue = property.value as? Bool, switchIndex < switches.count {
        switches[switchIndex].isOn = boolValue
        switchIndex += 1
      } else if let stringValue = property.value as? String, pickerIndex < pickers.count {
        // Update picker selection if the current value matches one of the options
        if let optionIndex = pickers[pickerIndex].options.firstIndex(of: stringValue) {
          pickers[pickerIndex].selectedIndex = optionIndex
        }
        pickerIndex += 1
      }
    }
  }
}
