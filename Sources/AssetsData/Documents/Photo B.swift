extension Document {
  static let photoB = Document(
    id: "PHOTO_B",
    displayName: "Photo",
    image: Image("Items/Documents/photo_b.png"),

    pages: [
      """
      Soldiers have barricated Nørreport Station.
      """,
      "",
      """
      On the back there’s a handwritten note: “They knew before we did.”
      """
    ]
  )
}
