import Foundation
import OrderedCollections
import STBRectPack

final class InputPromptsDemo: RenderLoop {
  private lazy var promptRenderer = InputPromptsRenderer()
  private lazy var titleText = TextRenderer("Creato Display Bold", 18)!

  // Helper function to measure the actual width of a group
  private func measureGroupWidth(prompts: OrderedDictionary<String, [[String]]>) -> Float {
    var maxWidth: Float = 0

    // Measure the actual width for each input source and take the maximum
    for source in InputSource.allCases {
      let size = promptRenderer.measureHorizontal(prompts: prompts, inputSource: source)
      maxWidth = max(maxWidth, size.width)
    }

    return maxWidth
  }

  @MainActor func draw() {
    let ws = (Int32(WIDTH), Int32(HEIGHT))

    // Test rectangle in top-left corner to verify debug drawing works
    Debug.drawRect(x: 10, y: 10, width: 100, height: 50, windowSize: ws)

    // Layout constants
    let rowStep: Float = 40
    let rowsPerGroup = Float(InputSource.allCases.count)
    let groupHeight = rowStep * rowsPerGroup
    let titleAboveOffset: Float = 4
    let padding: Float = 16

    // Collect all groups and measure their sizes
    var groupData: [(title: String, prompts: OrderedDictionary<String, [[String]]>, width: Float, height: Float)] = []

    for (title, prompts) in InputPromptsRenderer.groups.reversed() {
      let measuredWidth = measureGroupWidth(prompts: prompts)
      let totalHeight = groupHeight + titleAboveOffset + titleText.scaledLineHeight + padding
      groupData.append((title: title, prompts: prompts, width: measuredWidth, height: totalHeight))
    }

    // Pack rectangles using STBRectPack
    let margin: Float = 16
    let spacing: Float = 8  // Spacing between rectangles
    let binWidth = WIDTH - Int(margin * 2)  // Leave margin on both sides
    let binHeight = HEIGHT - Int(margin * 2)

    // Add spacing to each rectangle size for packing
    let rectSizes = groupData.map { (width: Int($0.width + spacing), height: Int($0.height + spacing)) }

    let (packedRects, allPacked) = RectPacking.pack(
      binWidth: binWidth,
      binHeight: binHeight,
      sizes: rectSizes,
      heuristic: .skylineBL
    )

    // Find the total height of the packed block to position it from bottom
    let maxPackedY = packedRects.map { $0.y + Int(groupData[$0.id].height) }.max() ?? 0
    let totalPackedHeight = maxPackedY

    // Draw each group at its packed position
    for (index, group) in groupData.enumerated() {
      guard index < packedRects.count else { continue }
      let packed = packedRects[index]
      guard packed.wasPacked else { continue }

      // Convert packed coordinates to screen coordinates (bottom-right aligned)
      // Position the entire packed block at the bottom-right of the screen
      let screenX = Float(WIDTH) - margin - Float(packed.x + Int(group.width))
      let screenY = Float(HEIGHT) - margin - Float(totalPackedHeight - packed.y)

      // Draw title
      let titleWidth = titleText.measureWidth(group.title)
      let titleX = screenX + Float(group.width) - titleWidth
      let titleBaselineY = screenY + Float(group.height) - padding
      titleText.draw(
        group.title, at: (titleX, titleBaselineY), windowSize: ws, color: (0.75, 0.75, 0.75, 1), anchor: .baselineLeft)

      // Draw input prompts for each source
      for (i, source) in InputSource.allCases.reversed().enumerated() {
        let y = screenY + Float(i) * rowStep
        let rightX = screenX + Float(group.width)
        promptRenderer.drawHorizontal(
          prompts: group.prompts, inputSource: source, windowSize: ws, origin: (rightX, y), anchor: .bottomRight)
      }

      // Draw debug rectangle around the packed group
      Debug.drawRect(
        x: screenX, y: screenY, width: Float(group.width), height: Float(group.height),
        windowSize: ws, lineWidth: 2.0
      )
    }
  }
}
