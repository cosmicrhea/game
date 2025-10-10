import GL
import GLFW
import GLMath

/// A reusable grid layout component with keyboard and mouse navigation
public final class GridLayout<T> {
  // MARK: - Configuration
  public let columns: Int
  public let rows: Int
  public let padding: Float
  public let itemSize: Float
  public let textHeight: Float

  // MARK: - State
  public private(set) var selectedIndex: Int = 0
  public private(set) var hoveredIndex: Int? = nil

  // MARK: - Items
  private var items: [T] = []

  // MARK: - Callbacks
  public var onItemSelected: ((T, Int) -> Void)?
  public var onItemHovered: ((T?, Int?) -> Void)?

  // MARK: - Input State
  private var lastMousePosition: Point = .zero
  private var isMouseOverGrid: Bool = false
  private var keyStates: Set<Keyboard.Key> = []

  public init(
    columns: Int,
    rows: Int,
    padding: Float = 8,
    itemSize: Float = 80,
    textHeight: Float = 20
  ) {
    self.columns = columns
    self.rows = rows
    self.padding = padding
    self.itemSize = itemSize
    self.textHeight = textHeight
  }

  // MARK: - Public Methods

  /// Sets the items to display in the grid
  public func setItems(_ items: [T]) {
    self.items = items
    // Clamp selected index to valid range
    if selectedIndex >= items.count {
      selectedIndex = max(0, items.count - 1)
    }
  }

  /// Updates the grid with input handling
  public func update(deltaTime: Float) {
    // Input handling will be done through the RenderLoop callbacks
    // This method is kept for future use
  }

  /// Handle keyboard input from RenderLoop
  public func handleKeyPressed(_ key: Keyboard.Key) {
    switch key {
    case .w, .up:
      moveSelection(direction: .up)
    case .s, .down:
      moveSelection(direction: .down)
    case .a, .left:
      moveSelection(direction: .left)
    case .d, .right:
      moveSelection(direction: .right)
    default:
      break
    }
  }

  /// Handle mouse movement from RenderLoop
  public func handleMouseMove(x: Double, y: Double) {
    // Flip Y coordinate to match screen coordinates
    let flippedY = Float(HEIGHT) - Float(y)
    let mousePosition = Point(Float(x), flippedY)
    lastMousePosition = mousePosition

    // Check if mouse is over grid
    let totalWidth = Float(WIDTH) - (padding * 2)
    let totalHeight = Float(HEIGHT) - (padding * 2)
    let gridRect = Rect(
      x: padding,
      y: padding,
      width: totalWidth,
      height: totalHeight
    )

    isMouseOverGrid = contains(point: mousePosition, in: gridRect)

    if isMouseOverGrid {
      // Find which item the mouse is over
      let cellWidth = (totalWidth - (Float(columns - 1) * padding)) / Float(columns)
      let cellHeight = (totalHeight - (Float(rows - 1) * padding)) / Float(rows)

      let relativeX = mousePosition.x - padding
      let relativeY = mousePosition.y - padding

      let col = Int(relativeX / (cellWidth + padding))
      let row = Int(relativeY / (cellHeight + padding))

      let newHoveredIndex = row * columns + col

      if newHoveredIndex != hoveredIndex && newHoveredIndex < items.count {
        hoveredIndex = newHoveredIndex
        onItemHovered?(items[newHoveredIndex], newHoveredIndex)
      }
    } else {
      if hoveredIndex != nil {
        hoveredIndex = nil
        onItemHovered?(nil, nil)
      }
    }
  }

  /// Draws the grid with all items
  public func draw(
    renderer: @escaping (T, Rect, Bool, Bool) -> Void
  ) {
    // Calculate tight grid layout
    let totalWidth = Float(WIDTH) - (padding * 2)
    let totalHeight = Float(HEIGHT) - (padding * 2)

    // Calculate cell size based on available space and padding
    let cellWidth = (totalWidth - (Float(columns - 1) * padding)) / Float(columns)
    let cellHeight = (totalHeight - (Float(rows - 1) * padding)) / Float(rows)

    // Draw each item in the grid
    for (index, item) in items.enumerated() {
      let row = index / columns
      let col = index % columns

      // Calculate position with tight spacing
      let x = padding + Float(col) * (cellWidth + padding)
      let y = padding + Float(row) * (cellHeight + padding)

      // Center the item within the cell
      let itemX = x + (cellWidth - itemSize) / 2
      let itemY = y + (cellHeight - itemSize - textHeight - 4) / 2

      let itemRect = Rect(
        x: itemX,
        y: itemY,
        width: itemSize,
        height: itemSize
      )

      let isSelected = selectedIndex == index
      let isHovered = hoveredIndex == index

      // Draw tasteful border around each item
      drawItemBorder(itemRect, isSelected: isSelected, isHovered: isHovered)

      // Let the caller render everything in this rect
      renderer(item, itemRect, isSelected, isHovered)
    }
  }

  // MARK: - Private Methods

  private enum Direction {
    case up, down, left, right
  }

  private func contains(point: Point, in rect: Rect) -> Bool {
    return point.x >= rect.origin.x && point.x <= rect.origin.x + rect.size.width && point.y >= rect.origin.y
      && point.y <= rect.origin.y + rect.size.height
  }

  private func moveSelection(direction: Direction) {
    let oldIndex = selectedIndex
    var newIndex = selectedIndex

    switch direction {
    case .up:
      newIndex = max(0, selectedIndex - columns)
    case .down:
      newIndex = min(items.count - 1, selectedIndex + columns)
    case .left:
      if selectedIndex % columns > 0 {
        newIndex = selectedIndex - 1
      }
    case .right:
      if selectedIndex % columns < columns - 1 && selectedIndex < items.count - 1 {
        newIndex = selectedIndex + 1
      }
    }

    if newIndex != oldIndex && newIndex < items.count {
      selectedIndex = newIndex
      onItemSelected?(items[selectedIndex], selectedIndex)
    }
  }

  private func drawItemBorder(_ rect: Rect, isSelected: Bool, isHovered: Bool) {
    // Draw tasteful border with different styles for different states
    if isSelected {
      // Selected: bright border with slight glow effect
      rect.frame(with: .white, lineWidth: 2.0)
      // Add a subtle inner glow
      let innerRect = rect.insetBy(dx: 2, dy: 2)
      innerRect.frame(with: .white.withAlphaComponent(0.3), lineWidth: 1.0)
    } else if isHovered {
      // Hovered: subtle border
      rect.frame(with: .white.withAlphaComponent(0.6), lineWidth: 1.5)
    } else {
      // Default: very subtle border
      rect.frame(with: .white.withAlphaComponent(0.2), lineWidth: 1.0)
    }
  }
}
