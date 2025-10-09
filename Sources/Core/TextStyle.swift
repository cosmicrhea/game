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
}
