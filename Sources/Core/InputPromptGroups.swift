import Foundation
import OrderedCollections

public enum PromptGroup: String, CaseIterable {
  case inventory
  case itemPickup = "Item Pickup"
  case menuRoot = "Menu Root"
  case menu = "Menu"
  case documentView = "Document View"
  case `continue` = "Continue"
  case modelView = "Model View"
  case itemView = "Item View"
  case mapView = "Map View"

  @MainActor public static let prompts: OrderedDictionary<PromptGroup, OrderedDictionary<String, [[String]]>> = [
    .inventory: [
      "Move": [["keyboard_option"], ["xbox_button_color_x"], ["playstation_button_color_square"]],
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Return": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .itemPickup: [
      "Continue": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .menuRoot: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .menu: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Return": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .documentView: [
      "Change Page": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    ],
    .`continue`: [
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .modelView: [
      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .itemView: [
      "Rotate": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .mapView: [
      "Change Floor": [["keyboard_arrows_vertical"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]],
      "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
  ]
}

public struct InputPromptGroups {
  public static let groups: OrderedDictionary<String, OrderedDictionary<String, [[String]]>> = [
    "Item Pickup": [
      "Continue": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],

    "Menu Root": [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],

    "Menu": [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      // "Return": [["keyboard_escape"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Return": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    "Document View": [
      "Change Page": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
      // "Continue": [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    ],

    "Continue": [
      // "Continue": [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],

    "Model View": [
      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    //    "Document View": [
    //      "Flip Pages": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
    //      // "Continue": [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    //      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    //    ],

    //    "Model View": [
    //      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
    //      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    //      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    //    ],

    "Item View": [
      "Rotate": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    "Map View": [
      // "Change Floor": [["keyboard_q", "keyboard_e"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]],
      "Change Floor": [["keyboard_arrows_vertical"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]],
      "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      // "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
  ]
}
