import GL
import GLFW
import GLMath

/// A specialized SlotGrid for displaying documents
@MainActor
public final class DocumentSlotGrid {
  // MARK: - Configuration
  public var columns: Int
  public var rows: Int
  public var slotSize: Float
  public var spacing: Float
  public var cornerRadius: Float
  public var radialGradientStrength: Float
  public var selectionWraps: Bool

  // MARK: - State
  public private(set) var gridPosition: Point = Point(0, 0)
  public private(set) var selectedIndex: Int
  public private(set) var hoveredIndex: Int? = nil

  // MARK: - Rendering
  private var slotEffect = GLScreenEffect("Common/Slot")

  // MARK: - Colors
  public var slotColor = Color.slotBackground
  public var borderColor = Color.slotBorder
  public var borderHighlight = Color.slotBorderHighlight
  public var borderShadow = Color.slotBorderShadow

  // MARK: - Slot Properties
  public var borderThickness: Float = 8.0
  public var noiseScale: Float = 0.02
  public var noiseStrength: Float = 0.3

  // MARK: - Tinting
  public var tint: Color? = nil

  // MARK: - Selection Colors
  public var selectedSlotColor = Color.slotSelected
  public var hoveredSlotColor = Color.slotHovered

  // MARK: - Selection Callback
  public var onDocumentSelected: ((Document?) -> Void)?

  // MARK: - Slot Data
  public var slotData: [DocumentSlotData?] = []

  public init(
    columns: Int,
    rows: Int,
    slotSize: Float = 128.0,
    spacing: Float = 8.0,
    cornerRadius: Float = 8.0,
    radialGradientStrength: Float = 0.6,
    selectionWraps: Bool = false
  ) {
    self.columns = columns
    self.rows = rows
    self.slotSize = slotSize
    self.spacing = spacing
    self.cornerRadius = cornerRadius
    self.radialGradientStrength = radialGradientStrength
    self.selectionWraps = selectionWraps
    // Start selection in bottom-left corner (now index 0)
    self.selectedIndex = 0
  }

  // MARK: - Public Methods

  /// Set the grid position (top-left corner)
  public func setPosition(_ position: Point) {
    gridPosition = position
  }

  /// Set the slot data array (should match the grid size)
  public func setSlotData(_ data: [DocumentSlotData?]) {
    slotData = data
  }

  /// Get slot data at a specific index
  public func getSlotData(at index: Int) -> DocumentSlotData? {
    guard index >= 0 && index < slotData.count else { return nil }
    return slotData[index]
  }

  /// Set slot data at a specific index
  public func setSlotData(_ data: DocumentSlotData?, at index: Int) {
    guard index >= 0 && index < slotData.count else { return }
    slotData[index] = data
  }

  /// Get the total size of the grid
  public var totalSize: Size {
    let totalWidth = Float(columns) * slotSize + Float(columns - 1) * spacing
    let totalHeight = Float(rows) * slotSize + Float(rows - 1) * spacing
    return Size(totalWidth, totalHeight)
  }

  /// Get the position of a specific slot by index
  public func slotPosition(at index: Int) -> Point {
    let col = index % columns
    let row = index / columns

    let x = gridPosition.x + Float(col) * (slotSize + spacing)
    // Flip Y coordinate so bottom row is row 0
    let y = gridPosition.y + Float(rows - 1 - row) * (slotSize + spacing)

    return Point(x, y)
  }

  /// Get the slot index at a given screen position
  public func slotIndex(at position: Point) -> Int? {
    let relativeX = position.x - gridPosition.x
    let relativeY = position.y - gridPosition.y

    // Check if position is within grid bounds
    if relativeX < 0 || relativeY < 0 {
      return nil
    }

    let col = Int(relativeX / (slotSize + spacing))
    let visualRow = Int(relativeY / (slotSize + spacing))

    // Convert visual row (bottom=0) to logical row (top=0)
    let row = rows - 1 - visualRow

    // Check if within valid grid
    if col < 0 || col >= columns || row < 0 || row >= rows {
      return nil
    }

    // Check if position is within the actual slot (not in spacing)
    let slotStartX = Float(col) * (slotSize + spacing)
    let slotStartY = Float(visualRow) * (slotSize + spacing)
    let slotEndX = slotStartX + slotSize
    let slotEndY = slotStartY + slotSize

    if relativeX < slotStartX || relativeX > slotEndX || relativeY < slotStartY || relativeY > slotEndY {
      return nil
    }

    return row * columns + col
  }

  /// Update hover state based on mouse position
  public func updateHover(at mousePosition: Point) {
    hoveredIndex = slotIndex(at: mousePosition)
  }

  /// Clear hover state
  public func clearHover() {
    hoveredIndex = nil
  }

  /// Set the selected slot index
  public func setSelected(_ index: Int) {
    if index >= 0 && index < columns * rows {
      selectedIndex = index
    }
  }

  /// Move selection in a direction
  /// Returns true if the selection actually moved, false if it hit an edge and wrapping is disabled
  @discardableResult
  public func moveSelection(direction: Direction) -> Bool {
    let currentCol = selectedIndex % columns
    let currentRow = selectedIndex / columns

    var newCol = currentCol
    var newRow = currentRow

    switch direction {
    case .up:
      if currentRow < rows - 1 {
        newRow = currentRow + 1
      } else if selectionWraps {
        newRow = 0  // Wrap to bottom row
      } else {
        return false  // Hit top edge, no wrapping
      }
    case .right:
      if currentCol < columns - 1 {
        newCol = currentCol + 1
      } else if selectionWraps {
        newCol = 0  // Wrap to leftmost column
      } else {
        return false  // Hit right edge, no wrapping
      }
    case .down:
      if currentRow > 0 {
        newRow = currentRow - 1
      } else if selectionWraps {
        newRow = rows - 1  // Wrap to top row
      } else {
        return false  // Hit bottom edge, no wrapping
      }
    case .left:
      if currentCol > 0 {
        newCol = currentCol - 1
      } else if selectionWraps {
        newCol = columns - 1  // Wrap to rightmost column
      } else {
        return false  // Hit left edge, no wrapping
      }
    }

    let newIndex = newRow * columns + newCol
    if newIndex != selectedIndex {
      selectedIndex = newIndex
      UISound.navigate()
      return true
    }
    return false
  }

  // MARK: - Input Handling

  /// Handle keyboard input for grid navigation
  public func handleKey(_ key: Keyboard.Key) -> Bool {
    switch key {
    case .w, .up:
      return moveSelection(direction: .down)  // W/Up moves down
    case .s, .down:
      return moveSelection(direction: .up)  // S/Down moves up
    case .a, .left:
      return moveSelection(direction: .left)
    case .d, .right:
      return moveSelection(direction: .right)
    case .f, .space, .enter:
      // Call document selection callback
      let document = slotData.indices.contains(selectedIndex) ? slotData[selectedIndex]?.document : nil
      onDocumentSelected?(document)
      return true
    default:
      return false
    }
  }

  /// Handle mouse movement for hover effects
  public func handleMouseMove(at position: Point) {
    updateHover(at: position)
  }

  /// Handle mouse click for selection
  public func handleMouseClick(at position: Point) -> Bool {
    if let slotIndex = slotIndex(at: position) {
      setSelected(slotIndex)
      let document = slotData.indices.contains(slotIndex) ? slotData[slotIndex]?.document : nil
      onDocumentSelected?(document)
      return true
    }
    return false
  }

  // MARK: - Rendering

  /// Draw the slot grid
  public func draw() {
    for i in 0..<(columns * rows) {
      let slotPosition = slotPosition(at: i)
      let centerPosition = Point(
        slotPosition.x + slotSize * 0.5,
        slotPosition.y + slotSize * 0.5
      )

      // Determine slot color based on state
      var currentSlotColor = slotColor
      if i == selectedIndex {
        currentSlotColor = selectedSlotColor
      } else if i == hoveredIndex {
        currentSlotColor = hoveredSlotColor
      }

      // Apply tint if specified
      if let tint = tint {
        currentSlotColor = Color(
          currentSlotColor.red * tint.red,
          currentSlotColor.green * tint.green,
          currentSlotColor.blue * tint.blue,
          currentSlotColor.alpha
        )
      }

      // Draw the slot
      slotEffect.draw { shader in
        shader.setVec2("uPanelSize", value: (slotSize, slotSize))
        shader.setVec2("uPanelCenter", value: (centerPosition.x, centerPosition.y))
        shader.setFloat("uBorderThickness", value: borderThickness)
        shader.setFloat("uCornerRadius", value: cornerRadius)
        shader.setFloat("uNoiseScale", value: noiseScale)
        shader.setFloat("uNoiseStrength", value: noiseStrength)
        shader.setFloat("uRadialGradientStrength", value: radialGradientStrength)

        // Set colors
        shader.setVec3(
          "uPanelColor", value: (x: currentSlotColor.red, y: currentSlotColor.green, z: currentSlotColor.blue))
        shader.setVec3("uBorderColor", value: (x: borderColor.red, y: borderColor.green, z: borderColor.blue))
        shader.setVec3(
          "uBorderHighlight", value: (x: borderHighlight.red, y: borderHighlight.green, z: borderHighlight.blue))
        shader.setVec3("uBorderShadow", value: (x: borderShadow.red, y: borderShadow.green, z: borderShadow.blue))
      }

      // Draw document image if slot has data
      if i < slotData.count, let slotData = slotData[i], let document = slotData.document, let image = document.image {
        let imageSize = min(slotSize * 0.8, min(image.naturalSize.width, image.naturalSize.height))
        let imageRect = Rect(
          x: slotPosition.x + (slotSize - imageSize) * 0.5,
          y: slotPosition.y + (slotSize - imageSize) * 0.5,
          width: imageSize,
          height: imageSize
        )

        // Apply opacity based on discovery status
        let opacity: Float = slotData.isDiscovered ? 1.0 : 0.25
        image.draw(in: imageRect, tint: Color.white.withAlphaComponent(opacity))
      }
    }
  }
}
