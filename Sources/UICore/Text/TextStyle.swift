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
    fontSize: 24,
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
    strokeWidth: 2,
    strokeColor: Color(red: 0.078, green: 0.059, blue: 0.055, alpha: 1.0)
  )
}
