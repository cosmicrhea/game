extension Document {
  static let siezedCargo = Document(
    id: "SIEZED_CARGO",
    displayName: "Cargo Memo",
    image: Image("Items/Documents/siezed_cargo.png"),

    frontMatter: """
      DDIS INTERNAL MEMO

      FILE REF: CARGO-XFR-392
      ORIGIN: KASTELLET / FIELD DESK 37
      DATE: 19 SEPTEMBER, 1983
      """,

    pages: [
      """
      Point of Origin:
      Perring Pharmaceuticals, Amager, DK

      Destination:
      [REDACTED], Västerbotten County, SE

      Cargo ID:
      RX-212 / "Crystalline Substrate, Type-R"
      """,

      """
      Declared Contents:
      Expired vaccine batches (x24 crates)

      Customs Clearance:
      Fast-tracked via diplomatic channel (DCH-71A)
      """,

      """
      Flagged Irregularities:

      - Weight discrepancy: Declared 720 kg, actual 1190 kg.

      - Seal tampering on 6 of 24 containers.

      - Internal radiation spike logged at Øresund checkpoint.
      """,
      // "Markings on crate interiors resemble fractal growth patterns — not consistent with packing materials."

      """
      DDIS Field Notes:

      - Exterior crates marked with Perring seal, but interior packaging unlabelled.

      - Substance appears dormant but reacts to proximity.

      - Sample stored under blackout protocol; awaiting transfer to B-Site.

      """,
      //      Handwritten Annotation (unconfirmed):
      //      "This isn't shipping. It's dumping." — Agent K.M.

      """
      TEMPORARY CLASSIFICATION:
      OBSIDIAN HOLD

      NO DIGITAL REPLICATION AUTHORIZED

      END OF FILE
      """,
    ]
  )
}
