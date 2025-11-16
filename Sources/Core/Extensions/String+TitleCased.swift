extension String {
  private static let acronyms = [
    "SDF",
    "UI",
  ]

  public var titleCased: String {
    let spaced = replacingOccurrences(
      of: #"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])"#,
      with: " ",
      options: .regularExpression
    )
    let capitalized = spaced.capitalized

    return capitalized.components(separatedBy: " ").map { word in
      let uppercased = word.uppercased()
      if Self.acronyms.contains(uppercased) {
        return uppercased
      }
      return word
    }.joined(separator: " ")
  }
}
