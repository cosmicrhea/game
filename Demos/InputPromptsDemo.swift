import Foundation
import OrderedCollections

final class InputPromptsDemo: RenderLoop {

  private let kmAtlas = AtlasImageRenderer("UI/InputPrompts/keyboard-mouse.xml")
  private let psAtlas = AtlasImageRenderer("UI/InputPrompts/playstation.xml")
  private let xbAtlas = AtlasImageRenderer("UI/InputPrompts/xbox.xml")

  private lazy var km = InputPromptsRenderer(atlas: kmAtlas, labelFontName: "Creato Display Bold", labelPx: 28)
  private lazy var ps = InputPromptsRenderer(atlas: psAtlas, labelFontName: "Creato Display Bold", labelPx: 28)
  private lazy var xb = InputPromptsRenderer(atlas: xbAtlas, labelFontName: "Creato Display Bold", labelPx: 28)
  private lazy var titleText = TextRenderer("Creato Display Bold", 18)!

  init() {
    [km, ps, xb].forEach { $0.labelBaselineOffset = -16 }
  }

  @MainActor func draw() {
    let ws = (Int32(WIDTH), Int32(HEIGHT))

    // Layout constants for grouping
    let rightX = Float(WIDTH) - 24
    let baseY: Float = 24
    let rowStep: Float = 40
    let rowsPerGroup: Float = 3
    let groupHeight = rowStep * rowsPerGroup
    let titleAboveOffset: Float = 18
    let groupGap: Float = 48

    // Ordered groups: title -> ordered prompts map
    var groups = OrderedDictionary<String, OrderedDictionary<String, [[String]]>>()
    groups["Item Inspection"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Rotate", [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]]),
        ("Zoom", [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]]),
        ("Reset", [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]]),
        ("Return", [["keyboard_escape"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )
    groups["Item Inspection 2"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Rotate", [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]]),
        ("Zoom", [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]]),
        ("Reset", [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]]),
        ("Return", [["keyboard_escape"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )

    var groupIndex: Int = 0
    for (title, prompts) in groups {
      let groupBaseY = baseY + Float(groupIndex) * (groupHeight + groupGap)

      let titleWidth = titleText.measureWidth(title)
      let titleX = rightX - titleWidth
      let titleBaselineY = groupBaseY + groupHeight + titleAboveOffset
      titleText.draw(
        title, at: (titleX, titleBaselineY), windowSize: ws, color: (0.75, 0.75, 0.75, 1), anchor: .baselineLeft)

      km.drawHorizontal(
        prompts: prompts, inputSource: .keyboardMouse, windowSize: ws, origin: (rightX, groupBaseY + 0 * rowStep),
        anchor: .bottomRight)
      ps.drawHorizontal(
        prompts: prompts, inputSource: .playstation, windowSize: ws, origin: (rightX, groupBaseY + 1 * rowStep),
        anchor: .bottomRight)
      xb.drawHorizontal(
        prompts: prompts, inputSource: .xbox, windowSize: ws, origin: (rightX, groupBaseY + 2 * rowStep),
        anchor: .bottomRight)

      groupIndex += 1
    }
  }
}
