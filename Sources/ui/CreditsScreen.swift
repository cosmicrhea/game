import Foundation
import GL
import GLFW
import GLMath
import ImageFormats

private let nameStyle = TextStyle(
  fontName: "Creato Display Bold",
  fontSize: 24,
  color: .white,
  lineHeight: 1.3
)

private let categoryStyle = nameStyle
  .withColor(.gray500)
  .withAlignment(.right)

private let sectionGap: Float = 0
private let initialScrollOffset = Engine.viewportSize.height * 1.2

final class CreditsScreen: RenderLoop {
  private let promptList = PromptList(.skip)

  // Animation state
  private var scrollOffset: Float = initialScrollOffset
  private var scrollSpeed: Float = 72.0  // pixels per second
  private var scrollTurbo: Bool = false
  private var totalContentHeight: Float = 0.0

  // Offscreen rendering
  private var creditsImage: Image?

  func onKey(window: GLFWWindow, key: Keyboard.Key, scancode: Int32, state: ButtonState, mods: Keyboard.Modifier) {
    if key == .space { scrollTurbo = state == .pressed }
  }

  func onMouseButton(window: GLFWWindow, button: Mouse.Button, state: ButtonState, mods: Keyboard.Modifier) {
    if button == .left { scrollTurbo = state == .pressed }
  }

  func update(deltaTime: Float) {
    // Create offscreen image if not exists
    if creditsImage == nil {
      // Calculate total content height only once when creating the image
      calculateTotalContentHeight()
      createCreditsImage()
    }

    // Update scroll position
    scrollOffset -= scrollSpeed * (scrollTurbo ? 16 : 1) * deltaTime

    // Loop back to start when the credits have scrolled completely off screen
    // The image is drawn at yPosition = screenHeight - scrollOffset
    // When the entire image has scrolled past the top of the screen, reset
    let screenHeight = Engine.viewportSize.height
    if scrollOffset < -totalContentHeight - screenHeight {
      scrollOffset = initialScrollOffset
    }
  }

  private func calculateTotalContentHeight() {
    var height: Float = 0.0

    for (category, names) in CreditsData.credits {
      // Get actual height of category text
      let categoryBounds = category.boundingRect(with: categoryStyle)
      // Get actual height of names as multiline string
      let namesText = names.sorted().joined(separator: "\n")
      let namesBounds = namesText.boundingRect(with: nameStyle, wrapWidth: Float.greatestFiniteMagnitude)
      height += max(categoryBounds.size.height, namesBounds.size.height)
      height += sectionGap  // Space between sections
    }

    // Add logo grid height
    let logoSize: Float = 96.0
    let logoSpacing: Float = 24.0
    let totalRows = CreditsData.logos.count
    let logoGridHeight = Float(totalRows) * logoSize + Float(totalRows - 1) * logoSpacing + logoSpacing * 2
    print(
      "logoGridHeight: \(logoGridHeight), totalRows: \(totalRows)")
    totalContentHeight = height + logoGridHeight
  }

  func draw() {
    // Set black background
    GraphicsContext.current?.renderer.setClearColor(.black)

    // Draw the offscreen credits image with scrolling
    if let creditsImage = creditsImage {
      let screenHeight = Engine.viewportSize.height
      let yPosition = screenHeight - scrollOffset
      let drawPoint = Point(0, yPosition.rounded(.down))

      creditsImage.draw(at: drawPoint)
    }

    promptList.draw()
  }

  private func calculateColumnWidths() -> (left: Float, right: Float) {
    var maxCategoryWidth: Float = 0.0
    var maxNameWidth: Float = 0.0

    for (category, names) in CreditsData.credits {
      // Find widest category
      let categoryBounds = category.boundingRect(with: categoryStyle)
      maxCategoryWidth = max(maxCategoryWidth, categoryBounds.size.width)

      // Find widest name (check individual names for width)
      for name in names {
        let nameBounds = name.boundingRect(with: nameStyle)
        maxNameWidth = max(maxNameWidth, nameBounds.size.width)
      }
    }

    return (left: maxCategoryWidth, right: maxNameWidth)
  }

  private func createCreditsImage() {
    let imageHeight = totalContentHeight * 1.5  // Make it taller to ensure logos fit
    let imageSize = Size(Engine.viewportSize.width, imageHeight)

    creditsImage = Image(size: imageSize, pixelScale: 1.0, isFlipped: true) {
      // Render all credits content to the offscreen image with flipped coordinates
      self.renderCreditsContent()
    }

    // Save the offscreen image for debugging
    if let image = creditsImage {
      do {
        try image.write(toFile: "/tmp/credits_debug.png")
        print("Saved credits image to /tmp/credits_debug.png")
      } catch {
        print("Failed to save credits image: \(error)")
      }
    }
  }

  private func renderCreditsContent() {
    let screenWidth = Float(Engine.viewportSize.width)

    // Calculate column widths
    let (leftColumnWidth, rightColumnWidth) = calculateColumnWidths()
    let gap: Float = 24.0 * 1.5

    // Center the columns horizontally
    let totalWidth = leftColumnWidth + gap + rightColumnWidth
    let leftColumnX = (screenWidth - totalWidth) / 2
    let rightColumnX = leftColumnX + leftColumnWidth + gap

    print(
      "Column positions: left=\(leftColumnX), right=\(rightColumnX), widths: \(leftColumnWidth)x\(rightColumnWidth)")
    print("GraphicsContext isFlipped: \(GraphicsContext.current?.isFlipped ?? false)")

    var currentY: Float = 0  // Start at the top of the image (Y=0 in flipped coordinates)

    for (category, names) in CreditsData.credits {
      print("Drawing category: '\(category)' at Y: \(currentY)")

      // Draw category (gray text, right-aligned in left column)
      category.draw(
        at: Point(leftColumnX, currentY),
        style: categoryStyle,
        wrapWidth: leftColumnWidth,
        anchor: .topLeft
      )

      // Get actual height of category for positioning names
      let categoryBounds = category.boundingRect(with: categoryStyle)
      var nameY = currentY

      // Draw names as a single multiline string (white text, left-aligned in right column) - sorted alphabetically
      let namesText = names.sorted().joined(separator: "\n")
      print("Drawing names: '\(namesText.prefix(50))...' at Y: \(nameY)")
      namesText.draw(
        at: Point(rightColumnX, nameY),
        style: nameStyle,
        wrapWidth: Float.greatestFiniteMagnitude,
        anchor: .topLeft
      )
      let namesBounds = namesText.boundingRect(with: nameStyle, wrapWidth: Float.greatestFiniteMagnitude)
      nameY += namesBounds.size.height

      // Move to next section - go down (add Y in flipped coordinates)
      let totalNamesHeight = nameY - currentY
      currentY += categoryBounds.size.height + totalNamesHeight + sectionGap
    }

    // Add logo grid at the end
    renderLogoGrid(currentY: currentY)
  }

  private func renderLogoGrid(currentY: Float) {
    let logoSize: Float = 96.0  // Increased from 64.0
    let logoSpacing: Float = 24.0  // Increased proportionally
    let screenWidth = Engine.viewportSize.width

    // Position logos at the END of the credits (after currentY)
    // With flipped context, we can use normal Y coordinates (top-left origin)
    let logoStartY = currentY + logoSpacing * 2  // Start below the last credit

    for (rowIndex, logoRow) in CreditsData.logos.enumerated() {
      // Calculate the actual width needed for this row based on logo aspect ratios
      var rowWidth: Float = 0
      var logoWidths: [Float] = []

      for logo in logoRow {
        let logoAspectRatio = logo.naturalSize.width / logo.naturalSize.height
        let logoWidth = logoSize * logoAspectRatio
        logoWidths.append(logoWidth)
        rowWidth += logoWidth
      }

      // Add spacing between logos
      if logoRow.count > 1 {
        rowWidth += Float(logoRow.count - 1) * logoSpacing
      }

      let rowStartX = (screenWidth - rowWidth) / 2  // Center the row

      var currentX = rowStartX
      for (colIndex, logo) in logoRow.enumerated() {
        let x = currentX
        let y = logoStartY + Float(rowIndex) * (logoSize + logoSpacing)

        // Move to next logo position
        currentX += logoWidths[colIndex] + logoSpacing

        // Draw the logo image at its natural aspect ratio
        // Constrain by height so wide logos can be wide
        let logoAspectRatio = logo.naturalSize.width / logo.naturalSize.height
        let logoHeight = logoSize  // Always use the full height
        let logoWidth = logoSize * logoAspectRatio  // Let width scale naturally

        // Position the logo at the calculated position (no additional centering needed)
        let logoX = x
        let logoY = y + (logoSize - logoHeight) / 2  // Only center vertically within the row height

        let logoRect = Rect(x: logoX, y: logoY, width: logoWidth, height: logoHeight)
        logo.draw(in: logoRect)
      }
    }
  }

}
