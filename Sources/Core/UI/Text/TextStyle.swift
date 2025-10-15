extension TextStyle {
  static let `default` = TextStyle(
    fontName: "Determination",
    fontSize: 16,
    color: .white
  )

  static let titleScreen = TextStyle(
    fontName: "Broken Glass",
    fontSize: 96,
    color: .white
  )

  static let inputPrompt = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 28,
    color: .white.withAlphaComponent(0.95)
  )

  static let dialog = TextStyle(
    fontName: "Determination",
    fontSize: 24,
    color: .gray500
  )

  static let dialogEmphasis = TextStyle(
    fontName: dialog.fontName,
    fontSize: dialog.fontSize,
    color: .indigo
  )

  static let subtle: TextStyle = TextStyle(
    fontName: dialog.fontName,
    fontSize: dialog.fontSize,
    color: .gray700
  )

  static let document = TextStyle(
    fontName: "Creato Display Medium",
    fontSize: 24,
    color: Color(red: 0.745, green: 0.749, blue: 0.655, alpha: 1.0),
    //lineHeight: 1.2,
    strokeWidth: 2,
    strokeColor: Color(red: 0.078, green: 0.059, blue: 0.055, alpha: 1.0)
  )

  static let menuItem = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 32,
    color: .white,
    strokeWidth: 2,
    strokeColor: .gray700
  )

  static let menuItemDisabled = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 32,
    color: .gray500,
    strokeWidth: 2,
    strokeColor: .gray900
  )

  static let version = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 16,
    color: .gray700.withAlphaComponent(0.5)
  )

  static let contextMenu = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 22,
    color: .white,
    strokeWidth: 2,
    strokeColor: .black
  )

  static let contextMenuDisabled = TextStyle(
    fontName: "Creato Display Bold",
    fontSize: 22,
    color: .gray500.withAlphaComponent(0.95)

  )

  /// Creates a menu item style based on selection and disabled state
  static func menuItem(selected: Bool, disabled: Bool) -> TextStyle {
    let baseStyle = disabled ? menuItemDisabled : menuItem

    if selected && !disabled {
      // Red text with dark red stroke for selected items
      return
        baseStyle
        .withColor(.rose)
        .withStroke(width: 2, color: Color(0.3, 0.1, 0.1, 1.0))  // Dark red stroke
    } else if selected && disabled {
      // Dark red for disabled AND selected items
      return
        baseStyle
        .withColor(Color(0.4, 0.1, 0.1, 1.0))  // Dark red color
        .withStroke(width: 2, color: Color(0.2, 0.05, 0.05, 1.0))  // Darker red stroke
    } else if disabled {
      // Gray for disabled but not selected items
      return baseStyle.withColor(.gray500)
    } else {
      // Normal styling for unselected items
      return baseStyle.withColor(.gray300)
    }
  }
}
