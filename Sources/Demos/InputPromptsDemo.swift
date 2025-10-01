import Foundation

final class InputPromptsDemo: Demo {

  private let atlas = AtlasImageRenderer("UI/InputPrompts/keyboard-mouse.xml")
  private lazy var prompts = InputPromptsRenderer(atlas: atlas, labelFontName: "Creato Display Bold", labelPx: 28)

  init() {
    prompts.labelBaselineOffset = -16
  }

  @MainActor func draw() {
    // Fill the screen with examples: four quadrants
    let ws = (Int32(WIDTH), Int32(HEIGHT))

    let kmRows: [InputPromptsRenderer.Row] = [
      .init(iconNames: ["mouse_move"], label: "Rotate"),
      .init(iconNames: ["mouse_scroll_vertical"], label: "Zoom"),
      .init(iconNames: ["keyboard_r"], label: "Reset"),
      .init(iconNames: ["keyboard_escape"], label: "Return"),
    ]

    let xboxRows: [InputPromptsRenderer.Row] = [
      .init(iconNames: ["xbox_stick_l"], label: "Rotate"),
      .init(iconNames: ["xbox_stick_r_vertical"], label: "Zoom"),
      .init(iconNames: ["xbox_button_color_x"], label: "Reset"),
      .init(iconNames: ["xbox_button_color_b"], label: "Return"),
    ]

    // Bottom-right baseline style
    prompts.drawHorizontal(groups: kmRows, windowSize: ws)

    // Top-right column
    prompts.draw(rows: kmRows, windowSize: ws, origin: (Float(WIDTH) - 24, Float(HEIGHT) - 24), anchor: .topRight)

    // Top-left column
    prompts.draw(rows: xboxRows, windowSize: ws, origin: (24, Float(HEIGHT) - 24), anchor: .topLeft)

    // Bottom-left horizontal strip
    prompts.drawHorizontal(groups: xboxRows, windowSize: ws, origin: (24, 24), anchor: .bottomLeft)
  }
}
