import GL
import GLFW
import GLMath

/// A grid of slots with configurable spacing and layout
@MainActor
public final class SlotGrid {
  // MARK: - Configuration
  public let columns: Int
  public let rows: Int
  public let slotSize: Float
  public let spacing: Float

  // MARK: - State
  public private(set) var gridPosition: Point = Point(0, 0)
  public private(set) var selectedIndex: Int
  public private(set) var hoveredIndex: Int? = nil

  // MARK: - Rendering
  private var slotEffect = GLScreenEffect("Common/Slot")

  // MARK: - Colors
  public var slotColor = Color(0.1, 0.1, 0.1)
  public var borderColor = Color(0.4, 0.4, 0.4)
  public var borderHighlight = Color(0.6, 0.6, 0.6)
  public var borderShadow = Color(0.2, 0.2, 0.2)

  // MARK: - Slot Properties
  public var borderThickness: Float = 8.0
  public var cornerRadius: Float = 12.0
  public var radialGradientStrength: Float = 0.3
  public var noiseScale: Float = 0.02
  public var noiseStrength: Float = 0.3

  // MARK: - Tinting
  public var tint: Color? = nil  // Optional tint color for slots

  // MARK: - Selection Behavior
  /// Whether selection wraps around edges.
  public var selectionWraps: Bool = false

  // MARK: - Selection Colors
  public var selectedSlotColor = Color(0.15, 0.15, 0.15)
  public var hoveredSlotColor = Color(0.12, 0.12, 0.12)

  public init(
    columns: Int,
    rows: Int,
    slotSize: Float = 80.0,
    spacing: Float = 2.0
  ) {
    self.columns = columns
    self.rows = rows
    self.slotSize = slotSize
    self.spacing = spacing

    // Start selection in bottom-left corner (now index 0)
    self.selectedIndex = 0
  }

  // MARK: - Public Methods

  /// Set the grid position (top-left corner)
  public func setPosition(_ position: Point) {
    gridPosition = position
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

  // MARK: - Rendering

  /// Draw the slot grid
  public func draw() {
    for i in 0..<(columns * rows) {
      let slotPos = slotPosition(at: i)
      let centerPos = Point(
        slotPos.x + slotSize * 0.5,
        slotPos.y + slotSize * 0.5
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
        shader.setVec2("uPanelCenter", value: (centerPos.x, centerPos.y))
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
    }
  }
}

// MARK: - Direction Enum
public enum Direction {
  case up, down, left, right
}
