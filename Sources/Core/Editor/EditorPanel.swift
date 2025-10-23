import Foundation

public final class EditorPanel: OptionsPanel {
  private var editableProperties: [AnyEditableProperty] = []
  private var propertyGroups: [EditablePropertyGroup] = []
  private var sliders: [Slider] = []
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

      let sliderWidth = r.size.width * 0.55
      // Reserve space at the right edge for the slider's value label so it doesn't clip
      let valueLabelReserve: Float = 32
      let sliderX = r.origin.x + r.size.width - valueLabelReserve - sidePadding - sliderWidth
      let sliderY = r.origin.y + (r.size.height - 36) * 0.5
      let controlFrame = Rect(x: sliderX, y: sliderY, width: sliderWidth, height: 36)
      rows[i].control.frame = controlFrame
    }
  }

  /// Update the panel to show properties for a given Editing object
  public func updateForObject(_ object: Editing) {
    noEditorMessage = nil
    currentObject = object
    let properties = object.getEditableProperties()

    // Check if we have grouped properties
    if properties.first is EditablePropertyGroup {
      propertyGroups = properties.compactMap { $0 as? EditablePropertyGroup }
      editableProperties = []
    } else {
      editableProperties = properties.compactMap { $0 as? AnyEditableProperty }
      propertyGroups = []
    }

    generateControls()
  }

  /// Show a fallback message for non-editable objects
  public func showNoEditorMessage() {
    currentObject = nil
    editableProperties = []
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
          }
        }
      }
    } else {
      // Handle ungrouped properties
      for property in editableProperties {
        if let slider = createSliderForProperty(property) {
          sliders.append(slider)
          rows.append(Row(label: property.displayName, control: slider))
        }
      }
    }
    setRows(rows)
  }

  private func createSliderForProperty(_ property: AnyEditableProperty) -> Slider? {
    // Only create sliders for Float properties with valid ranges
    guard let range = property.validRange,
      let floatValue = property.value as? Float
    else {
      return nil
    }

    // Use smooth sliders in the editor for continuous control
    let slider = Slider(smooth: .zero, min: Float(range.lowerBound), max: Float(range.upperBound), value: floatValue)

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

  /// Update slider values when the underlying object properties change
  public func refreshValues() {
    guard let object = currentObject else { return }

    let properties = object.getEditableProperties()
    let currentProperties: [AnyEditableProperty]

    if properties.first is EditablePropertyGroup {
      currentProperties = propertyGroups.flatMap { $0.properties }
    } else {
      currentProperties = editableProperties
    }

    for (index, property) in currentProperties.enumerated() {
      guard index < sliders.count,
        let floatValue = property.value as? Float
      else { continue }

      sliders[index].value = floatValue
    }
  }
}
