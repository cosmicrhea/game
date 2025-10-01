import Foundation
import OrderedCollections

extension InputPromptsRenderer {
  // Ordered groups: title -> ordered prompts map
  static let groups = {
    var groups = OrderedDictionary<String, OrderedDictionary<String, [[String]]>>()
    groups["Menu"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Select", [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]),
        // ("Return", [["keyboard_escape"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
        ("Return", [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )
    groups["Document Viewer"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Flip Pages", [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]]),
        //        ("Continue", [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]),
        ("Continue", [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]),
      ]
    )
    groups["Model Viewer"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Hide Controls", [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]]),
        // ("Close", [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
        ("Close", [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )
    groups["Item Viewer"] = OrderedDictionary(
      uniqueKeysWithValues: [
        ("Rotate", [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]]),
        ("Zoom", [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]]),
        ("Reset", [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]]),
        // ("Close", [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
        ("Close", [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )
    groups["Map Viewer"] = OrderedDictionary(
      uniqueKeysWithValues: [
        //        ("Change Floor", [["keyboard_q", "keyboard_e"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]]),
        ("Change Floor", [["keyboard_arrows_vertical"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]]),
        ("Move", [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]]),
        ("Zoom", [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]]),
        ("Reset", [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]]),
        // ("Close", [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
        ("Close", [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]]),
      ]
    )
    return groups
  }()


}

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
