extension Item {
  // MARK: - Recovery

  static let morphine = Item(
    id: "morphine",
    kind: .recovery,
    name: "Morphine Sulfate",
    description: "Pills that restore a large amount of vitality.",
  )

  // MARK: - Mêlée

  static let knife = Item(
    id: "knife",
    kind: .weapon,
    name: "Military Knife",
    description: "This weapon is a veteran survivor’s first choice.",
  )

  // MARK: - Handguns

  static let glock17 = Item(
    id: "glock17",
    kind: .weapon,
    name: "Glock 17",
    description: "Compact 9mm pistol with selective fire capability.",
  )

  static let glock18 = Item(
    id: "glock18c",
    kind: .weapon,
    name: "Glock 18C",
    description: "Compact 9mm pistol with selective fire capability.",
  )

  static let sigp320 = Item(
    id: "sigp320",
    kind: .weapon,
    name: "SIG Sauer P320",
    description: "Modern striker-fired pistol with modular design.",
  )

  static let beretta92 = Item(
    id: "beretta92",
    kind: .weapon,
    name: "Beretta 92",
    description: "Compact 9mm pistol.",
  )

  static let fnx45 = Item(
    id: "fnx45",
    kind: .weapon,
    name: "FNX-45 Tactical",
    description: "Compact, reliable, and affordable 9mm pistol.",
  )

  // MARK: - Shotguns

  static let remington870 = Item(
    id: "remington870",
    kind: .weapon,
    name: "Remington 870",
    description: "Classic 12-gauge shotgun with a wooden frame.",
  )

  static let spas12 = Item(
    id: "spas12",
    kind: .weapon,
    name: "SPAS-12",
    description: "A sporting shotgun with a 12-gauge barrel and a detachable magazine.",
  )

  // MARK: - SMGs

  static let mp5sd = Item(
    id: "mp5sd",
    kind: .weapon,
    name: "MP5SD",
    description: "Submachine gun with a high rate of fire and built-in suppressor.",
  )

  // MARK: - Ammo

  static let handgunAmmo = Item(
    id: "handgun_ammo",
    kind: .ammo,
    name: "9mm Ammunition",
    description: "Standard 9 millimeter rounds for handguns.",
  )

  // MARK: - Keys

  static let utilityKey = Item(
    id: "utility_key",
    name: "Utility Key",
    //realName: "Generator Key",
    description: "A key for utility cabinets.",
  )

  static let metroKey = Item(
    id: "metro_key",
    name: "Metro Key",
    description: "A rusty key attached to a Metro logo keychain.",
  )

  static let tagKey = Item(
    id: "tag_key",
    name: "Key with Tag",
    description: "A key with a blank tag. Odd.",
  )

  // MARK: - Other

  static let cryoGloves = Item(
    id: "cryo_gloves",
    name: "Cryogenic Gloves",
    description: "A pair of gloves suitable for handling supercooled liquids.",
  )

  static let lighter = Item(
    id: "lighter",
    name: "Lighter",
    description: "Simple butane lighter for lighting fires.",
  )
}
