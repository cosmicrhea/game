import OrderedCollections
import STBRectPack

final class PromptListDemo: RenderLoop {
  private lazy var promptRenderer = PromptList(axis: .horizontal)
  private let titleStyle = TextStyle(fontName: "CreatoDisplay-Bold", fontSize: 18, color: .white)

  // Helper function to measure the actual width of a group
  private func measureGroupWidth(prompts: OrderedDictionary<LocalizedStringResource, [[String]]>) -> Float {
    var maxWidth: Float = 0

    // Measure the actual width for each input source and take the maximum
    for source in InputSource.allCases {
      let size = promptRenderer.measureHorizontal(prompts: prompts, inputSource: source)
      maxWidth = max(maxWidth, size.width)
    }

    return maxWidth
  }

  func draw() {
    let ws = (Int32(Engine.viewportSize.width), Int32(Engine.viewportSize.height))

    // Layout constants
    let rowStep: Float = 40
    let rowsPerGroup = Float(InputSource.allCases.count)
    let groupHeight = rowStep * rowsPerGroup
    let titleAboveOffset: Float = -12
    let padding: Float = 16

    // Collect all groups and measure their sizes
    var groupData: [(title: String, prompts: OrderedDictionary<LocalizedStringResource, [[String]]>, width: Float, height: Float)] = []

    for (title, prompts) in PromptGroup.prompts.reversed() {
      let measuredWidth = measureGroupWidth(prompts: prompts)
      let totalHeight = groupHeight + titleAboveOffset + titleStyle.fontSize * 1.2 + padding
      groupData.append((title: title.rawValue.titleCased, prompts: prompts, width: measuredWidth, height: totalHeight))
    }

    // Pack rectangles using STBRectPack
    let marginX: Float = 56
    let marginY: Float = 12
    let spacingX: Float = 56  // Spacing between rectangles
    let spacingY: Float = 48  // Spacing between rectangles
    let binWidth = Int(Engine.viewportSize.width) - Int(marginX * 2)  // Leave margin on both sides
    let binHeight = Int(Engine.viewportSize.height) - Int(marginY * 2)

    // Add spacing to each rectangle size for packing
    let rectSizes = groupData.map { (width: Int($0.width + spacingX), height: Int($0.height + spacingY)) }

    let (packedRects, _) = RectPacking.pack(
      binWidth: binWidth,
      binHeight: binHeight,
      sizes: rectSizes,
      heuristic: .skylineBL
    )

    // Find the total height of the packed block to position it from bottom
    //    let maxPackedY = packedRects.map { $0.y + Int(groupData[$0.id].height) }.max() ?? 0
    let translateY = marginY

    // Draw each group at its packed position
    for (index, group) in groupData.enumerated() {
      guard index < packedRects.count else { continue }
      let packed = packedRects[index]
      guard packed.wasPacked else { continue }

      // Convert packed coordinates to screen coordinates (bottom-right aligned)
      // Translate the entire packed block to bottom-right
      let screenX = Float(GraphicsContext.current?.size.width ?? 1280) - marginX - Float(packed.x + Int(group.width))
      let screenY = translateY + Float(packed.y)

      // Draw title
      let titleColor = Color(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
      let titleStyleWithColor = TextStyle(
        fontName: titleStyle.fontName, fontSize: titleStyle.fontSize, color: titleColor)
      let titleWidth = group.title.size(with: titleStyleWithColor).width
      let titleX = screenX + Float(group.width) - titleWidth
      let titleBaselineY = screenY + Float(group.height) - padding
      group.title.draw(
        at: Point(titleX, titleBaselineY), style: titleStyleWithColor, anchor: .bottomLeft)

      // Draw input prompts for each source
      for (i, source) in InputSource.allCases.enumerated() {
        let y = screenY + Float(i) * rowStep
        let rightX = screenX + Float(group.width)
        promptRenderer.drawHorizontal(
          prompts: group.prompts, inputSource: source, windowSize: ws, origin: (rightX, y), anchor: .bottomRight)
      }

      if Config.current.wireframeMode {
        // Draw debug rectangle around the packed group
        Rect(x: screenX, y: screenY, width: Float(group.width), height: Float(group.height)).frame(with: .magenta)
      }
    }
  }
}
