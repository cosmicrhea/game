import OrderedCollections

public enum PromptGroup: String, CaseIterable {
  case skip
  case library
  case inventory
  case confirmCancel
  case itemStorage
  case itemStorageList
  // case itemStorageList(sortOrder: ItemSortOrder)
  case itemPickup
  case menuRoot
  case menu
  case documentView
  case `continue`
  case modelViewer
  case modelViewerControls
  case itemView
  case mapView

  // static let allCases: [PromptGroup] = [
  //   .skip,
  //   .library,
  //   .confirmCancel,
  //   .itemStorage,
  //   .itemStorageList(sortOrder: .key),
  //   .itemPickup,
  //   .menuRoot,
  //   .menu,
  //   .documentView,
  //   .`continue`,
  //   .modelViewer,
  //   .modelViewerControls,
  //   .itemView,
  //   .mapView,
  // ]

  @MainActor public static let prompts: OrderedDictionary<PromptGroup, OrderedDictionary<String, [[String]]>> = [
    .skip: [
      "Skip": [["keyboard_tab_icon"], ["xbox_button_color_x"], ["playstation_button_color_square"]]
    ],
    .library: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .confirmCancel: [
      "Confirm": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Cancel": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .itemStorage: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .itemStorageList: [
      "Sort": [["keyboard_option"], ["xbox_button_color_x"], ["playstation_button_color_square"]],
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .itemPickup: [
      "Continue": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .inventory: [
      "Move": [["keyboard_option"], ["xbox_button_color_x"], ["playstation_button_color_square"]],
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .menuRoot: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .menu: [
      "Select": [["keyboard_space_icon"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
      "Back": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .documentView: [
      "Change Page": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]],
    ],
    .`continue`: [
      "Continue": [["mouse_left"], ["xbox_button_color_a"], ["playstation_button_color_triangle"]]
    ],
    .modelViewer: [
      "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .modelViewerControls: [
      "Play": [["keyboard_space_icon"], ["xbox_stick_r_horizontal"], ["playstation_stick_r_horizontal"]],
      "Rotate": [["mouse_horizontal"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
    ],
    .itemView: [
      "Rotate": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
    .mapView: [
      //"Change Floor": [["keyboard_arrows_vertical"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]],
      "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
      "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
      "Reset": [["keyboard_r"], ["xbox_button_color_x"], ["playstation_button_color_cross"]],
      "Close": [["mouse_right"], ["xbox_button_color_b"], ["playstation_button_color_circle"]],
    ],
  ]
}
