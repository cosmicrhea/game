extension Document {
  static let execsRecording = Document(
    id: "EXECS_RECORDING",
    displayName: "Execs’ Recording",
    image: Image("Items/Documents/cassette_player.png"),

    frontMatter: """
      DDIS AUDIO TRANSCRIPT
      
      FILE REF: PERR-INT/432
      CLASSIFICATION: KONFIDENTIEL
      SOURCE: Cassette (seized during raid)
      DATE: 22 AUGUST, 1983
      """,

    pages: [
      """
      [00:12]
      Exec A: Do you have the shipment report?

      [00:15]
      Exec B: [REDACTED]

      [00:19]
      Exec A: That’s not what I was told. You said twenty-four containers, not—
      """,
      """
      [00:22]
      Exec B: Keep your voice down. We agreed: if [REDACTED] notices the excess weight, we lose everything.

      [00:31]
      Exec A: You’re still moving it through the Amager site?

      [00:33]
      Exec B: For now. But containment won’t last. The substrate is… growing.
      """,
      """
      [00:40]
      Exec A: Then shut it down. Shut it all down before [REDACTED].

      [00:45]
      Exec B: We can’t. You’ve seen the returns. Investors are—

      [00:51]
      [SEVERAL SECONDS REDACTED]
      """,
      """
      [01:03]
      Exec A: If the Danish side learns what we buried, the deal is finished.

      [01:06]
      [End of recording]
      """
    ]
  )
}
