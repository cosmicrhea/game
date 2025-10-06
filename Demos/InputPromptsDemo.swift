import Foundation
import OrderedCollections

final class InputPromptsDemo: RenderLoop {
  private lazy var promptRenderer = InputPromptsRenderer()
  private lazy var titleText = TextRenderer("Creato Display Bold", 18)!

  @MainActor func draw() {
    let ws = (Int32(WIDTH), Int32(HEIGHT))

    // Layout constants for grouping
    let rightX = Float(WIDTH) - 32
    let baseY: Float = 24
    let rowStep: Float = 40
    let rowsPerGroup = Float(InputSource.allCases.count)
    let groupHeight = rowStep * rowsPerGroup
    let titleAboveOffset: Float = 4
    let groupGap: Float = 48

    var groupIndex: Int = 0
    for (title, prompts) in InputPromptsRenderer.groups.reversed() {
      let groupBaseY = baseY + Float(groupIndex) * (groupHeight + groupGap)

      let titleWidth = titleText.measureWidth(title)
      let titleX = rightX - titleWidth
      let titleBaselineY = groupBaseY + groupHeight + titleAboveOffset
      titleText.draw(
        title, at: (titleX, titleBaselineY), windowSize: ws, color: (0.75, 0.75, 0.75, 1), anchor: .baselineLeft)

      for (i, source) in InputSource.allCases.reversed().enumerated() {
        let y = groupBaseY + Float(i) * rowStep
        promptRenderer.drawHorizontal(
          prompts: prompts, inputSource: source, windowSize: ws, origin: (rightX, y), anchor: .bottomRight)
      }

      groupIndex += 1
    }
  }
}
