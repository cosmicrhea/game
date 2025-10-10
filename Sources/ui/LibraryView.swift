import GL
import GLFW
import GLMath

final class LibraryView: RenderLoop {
  private var deltaTime: Float = 0.0
  private var selectedIndex: Int = 0
  private var hoveredIndex: Int? = nil

  // Grid configuration
  private let columns = 3
  private let rows = 6
  private let itemSize: Float = 96
  private let padding: Float = 8

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    let oldIndex = selectedIndex
    var newIndex = selectedIndex

    switch key {
    case .w, .up:
      newIndex = max(0, selectedIndex - columns)
    case .s, .down:
      newIndex = min(columns * rows - 1, selectedIndex + columns)
    case .a, .left:
      if selectedIndex % columns > 0 {
        newIndex = selectedIndex - 1
      }
    case .d, .right:
      if selectedIndex % columns < columns - 1 && selectedIndex < columns * rows - 1 {
        newIndex = selectedIndex + 1
      }
    default:
      break
    }

    if newIndex != oldIndex {
      selectedIndex = newIndex
      UISound.select()
    }
  }

  func onMouseMove(window: GLFWWindow, x: Double, y: Double) {
    // Flip Y coordinate to match screen coordinates
    let flippedY = Float(HEIGHT) - Float(y)
    let mousePosition = Point(Float(x), flippedY)

    // Calculate grid dimensions
    let totalWidth = Float(WIDTH) - (padding * 2)
    let totalHeight = Float(HEIGHT) - (padding * 2)
    let cellWidth = (totalWidth - (Float(columns - 1) * padding)) / Float(columns)
    let cellHeight = (totalHeight - (Float(rows - 1) * padding)) / Float(rows)

    // Check if mouse is over grid
    let gridRect = Rect(
      x: padding,
      y: padding,
      width: totalWidth,
      height: totalHeight
    )

    if mousePosition.x >= gridRect.origin.x && mousePosition.x <= gridRect.origin.x + gridRect.size.width
      && mousePosition.y >= gridRect.origin.y && mousePosition.y <= gridRect.origin.y + gridRect.size.height
    {
      // Find which item the mouse is over
      let relativeX = mousePosition.x - padding
      let relativeY = mousePosition.y - padding

      let col = Int(relativeX / (cellWidth + padding))
      let row = Int(relativeY / (cellHeight + padding))

      let newHoveredIndex = row * columns + col

      if newHoveredIndex != hoveredIndex && newHoveredIndex < columns * rows {
        hoveredIndex = newHoveredIndex
        UISound.select()
      }
    } else {
      if hoveredIndex != nil {
        hoveredIndex = nil
      }
    }
  }

  func draw() {
    // Set clear color to black
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Calculate grid dimensions
    let totalWidth = Float(WIDTH) - (padding * 2)
    let totalHeight = Float(HEIGHT) - (padding * 2)
    let cellWidth = (totalWidth - (Float(columns - 1) * padding)) / Float(columns)
    let cellHeight = (totalHeight - (Float(rows - 1) * padding)) / Float(rows)

    // Draw each grid item
    for index in 0..<(columns * rows) {
      let row = index / columns
      let col = index % columns

      // Calculate position
      let x = padding + Float(col) * (cellWidth + padding)
      let y = padding + Float(row) * (cellHeight + padding)

      // Center the item within the cell
      let itemX = x + (cellWidth - itemSize) / 2
      let itemY = y + (cellHeight - itemSize) / 2

      let itemRect = Rect(
        x: itemX,
        y: itemY,
        width: itemSize,
        height: itemSize
      )

      let isSelected = selectedIndex == index
      let isHovered = hoveredIndex == index

      // Draw the rect
      if isSelected {
        itemRect.fill(with: .white)
      } else if isHovered {
        itemRect.fill(with: .white.withAlphaComponent(0.5))
      } else {
        itemRect.frame(with: .white.withAlphaComponent(0.3), lineWidth: 2)
      }
    }
  }
}
