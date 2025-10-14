import GL
import GLFW
import GLMath
import STBRectPack

final class LibraryView: RenderLoop {
  private var deltaTime: Float = 0.0
  private var selectedIndex: Int = 0
  private var hoveredIndex: Int? = nil

  // Packed rectangles from RectPacking
  private var packedRects: [Rect] = []

  // All documents in order (including nil slots) - 3x5 grid (15 total)
  private let documents: [Document?] = {
    let allDocs = Document.all
    let emptySlots = Array(repeating: Document?.none, count: 15 - allDocs.count)
    return allDocs.map { $0 as Document? } + emptySlots
  }()

  // Discovered document IDs
  private var discoveredDocumentIDs: [String] = [
    "JARITS_JOURNAL",
    "METRO_NOTE",
    "PHOTO_A",
    "SIEZED_CARGO",
    "PHOTO_B",
    "EXECS_RECORDING",
    "PHOTO_C",
    "GLASPORT_REPORT",
    "PHOTO_D",
  ]

  // Grid configuration
  private let itemSize: Float = 96
  private let spacing: Float = 8

  init() {
    // Pack rectangles using RectPacking
    let binWidth = 800
    let binHeight = Int(Engine.viewportSize.height)

    let rectSizes = Array(
      repeating: (width: Int(itemSize + spacing), height: Int(itemSize + spacing)), count: documents.count)

    let (packed, _) = RectPacking.pack(
      binWidth: binWidth,
      binHeight: binHeight,
      sizes: rectSizes,
      heuristic: .skylineBL
    )

    // Calculate the actual height used by finding the maximum Y position
    let maxY = packed.map { Float($0.y) + itemSize + spacing }.max() ?? 0

    // Convert packed rectangles to our Rect type and center them
    let offsetX = (Float(Engine.viewportSize.width) - Float(binWidth)) / 2
    let offsetY = (Float(Engine.viewportSize.height) - maxY) / 2
    packedRects = packed.map { packedRect in
      Rect(
        x: Float(packedRect.x) + offsetX + spacing / 2,
        y: Float(packedRect.y) + offsetY + spacing / 2,
        width: itemSize,
        height: itemSize
      )
    }
  }

  func update(deltaTime: Float) {
    self.deltaTime = deltaTime
  }

  func onKeyPressed(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    let oldIndex = selectedIndex
    var newIndex = selectedIndex

    switch key {
    case .w, .up:
      newIndex = min(documents.count - 1, selectedIndex + 1)
    case .s, .down:
      newIndex = max(0, selectedIndex - 1)
    case .a, .left:
      newIndex = max(0, selectedIndex - 1)
    case .d, .right:
      newIndex = min(documents.count - 1, selectedIndex + 1)
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
    let flippedY = Float(Engine.viewportSize.height) - Float(y)
    let mousePosition = Point(Float(x), flippedY)

    // Check each packed rectangle for mouse collision
    var foundHover = false
    for index in 0..<packedRects.count {
      let itemRect = packedRects[index]

      // Check if mouse is over this specific square
      if itemRect.contains(mousePosition) {
        if index != hoveredIndex {
          hoveredIndex = index
          UISound.select()
        }
        foundHover = true
        break
      }
    }

    if !foundHover && hoveredIndex != nil {
      hoveredIndex = nil
    }
  }

  func draw() {
    // Set clear color to black
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw each packed rectangle
    for index in 0..<packedRects.count {
      let itemRect = packedRects[index]
      let isSelected = selectedIndex == index
      let isHovered = hoveredIndex == index

      // Draw rounded rectangle background
      let roundedRect = RoundedRect(
        itemRect,
        cornerRadius: 8
      )

      if isSelected {
        roundedRect.draw(color: Color.white.withAlphaComponent(0.2))
      } else if isHovered {
        roundedRect.draw(color: Color.white.withAlphaComponent(0.1))
      } else {
        roundedRect.draw(color: Color.white.withAlphaComponent(0.05))
      }

      // Draw rounded rectangle border
      roundedRect.stroke(color: Color.white.withAlphaComponent(0.3), lineWidth: 1)

      // Draw document image if it exists
      if let document = documents[index] {
        // Check if document is discovered
        let isDiscovered = document.id != nil && discoveredDocumentIDs.contains(document.id!)
        let opacity: Float = isDiscovered ? 1.0 : 0.25

        document.image?.draw(in: itemRect, tint: Color.white.withAlphaComponent(opacity))

        // Draw document name below the image
        if let displayName = document.displayName {
          let textY = itemRect.origin.y + itemRect.size.height + 4
          let textRect = Rect(
            x: itemRect.origin.x,
            y: textY,
            width: itemRect.size.width,
            height: 20
          )

          // Create text style
          let textStyle = TextStyle(
            fontName: "Squarewave",
            fontSize: 16,
            color: isSelected ? Color.white.withAlphaComponent(opacity) : Color.white.withAlphaComponent(0.8 * opacity),
            alignment: .center
          )

          // Draw the text centered in the rect
          displayName.draw(
            at: Point(textRect.origin.x + textRect.size.width / 2, textRect.origin.y + textRect.size.height / 2),
            style: textStyle,
            anchor: .topLeft
          )
        }
      } else {
        // Draw empty slot indicator
        let emptyText = "Empty"
        let textStyle = TextStyle(
          fontName: "Squarewave",
          fontSize: 14,
          color: Color.white.withAlphaComponent(0.3),
          alignment: .center
        )

        emptyText.draw(
          at: Point(itemRect.origin.x + itemRect.size.width / 2, itemRect.origin.y + itemRect.size.height / 2),
          style: textStyle,
          anchor: .topLeft
        )
      }
    }
  }
}
