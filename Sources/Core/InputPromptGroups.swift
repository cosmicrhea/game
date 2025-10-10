import Foundation
import OrderedCollections

public struct InputPromptGroups {
  public static let groups: OrderedDictionary<String, OrderedDictionary<String, [[String]]>> = [
    "Item Pickup": [
      "Continue": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],

    "Menu": [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      // "Return": [["keyboard_escape"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Return": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    "Document Viewer": [
      "Change Page": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
      // "Continue": [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    ],

    "Model Viewer": [
      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    //    "Document Viewer": [
    //      "Flip Pages": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
    //      // "Continue": [["keyboard_tab_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    //      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    //    ],

    //    "Model Viewer": [
    //      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
    //      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    //      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    //    ],

    "Item Viewer": [
      "Rotate": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      // "Close": [["keyboard_tab_icon"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],

    "Map Viewer": [
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
