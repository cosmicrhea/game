import OrderedCollections

private let usesColorIcons = false

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

  @MainActor public static let prompts:
    OrderedDictionary<PromptGroup, OrderedDictionary<LocalizedStringResource, [[String]]>> = [
      .skip: [
        "Skip": [
          ["keyboard_tab_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ]
      ],
      .library: [
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .confirmCancel: [
        "Confirm": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Cancel": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .itemStorage: [
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .itemStorageList: [
        "Sort": [
          ["keyboard_option"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ],
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .itemPickup: [
        "Continue": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ]
      ],
      .inventory: [
        "Move": [
          ["keyboard_option"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ],
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .menuRoot: [
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ]
      ],
      .menu: [
        "Select": [
          ["keyboard_space_icon"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
        "Back": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .documentView: [
        "Change Page": [["keyboard_arrows_horizontal"], ["xbox_dpad_horizontal"], ["playstation_dpad_horizontal"]],
        "Continue": [
          ["mouse_left"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ],
      ],
      .`continue`: [
        "Continue": [
          ["mouse_left"], ["xbox_button\(usesColorIcons ? "_color" : "")_a"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_cross"],
        ]
      ],
      .modelViewer: [
        "Hide Controls": [["keyboard_z"], ["xbox_button_menu"], ["playstation5_button_options"]],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .modelViewerControls: [
        "Play": [["keyboard_space_icon"], ["xbox_stick_r_horizontal"], ["playstation_stick_r_horizontal"]],
        "Rotate": [["mouse_horizontal"], ["xbox_stick_l"], ["playstation_stick_l"]],
        "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
        "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
        "Reset": [
          ["keyboard_r"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ],
      ],
      .itemView: [
        "Rotate": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
        "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
        "Reset": [
          ["keyboard_r"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
      .mapView: [
        //"Change Floor": [["keyboard_arrows_vertical"], ["xbox_dpad_vertical"], ["playstation_dpad_vertical"]],
        "Move": [["mouse_move"], ["xbox_stick_l"], ["playstation_stick_l"]],
        "Zoom": [["mouse_scroll_vertical"], ["xbox_stick_r_vertical"], ["playstation_stick_r_vertical"]],
        "Reset": [
          ["keyboard_r"], ["xbox_button\(usesColorIcons ? "_color" : "")_x"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_square"],
        ],
        "Close": [
          ["mouse_right"], ["xbox_button\(usesColorIcons ? "_color" : "")_b"],
          ["playstation_button\(usesColorIcons ? "_color" : "")_circle"],
        ],
      ],
    ]
}
