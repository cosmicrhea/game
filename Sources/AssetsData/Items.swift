private let usesRealGunNames = false

extension Item {
  // MARK: - Recovery

  static let morphine = Item(
    id: "morphine",
    kind: .recovery,
    name: "Morphine",
    description: "A painkiller that restores a large amount of vitality.",
  )

  // MARK: - Mêlée

  static let knife = Item(
    id: "knife",
    kind: .weapon(.melee),
    name: "Military Knife",
    description: "This weapon is a veteran survivor's first choice.",
  )

  // MARK: - Handguns

  static let glock17 = Item(
    id: "glock17",
    kind: .weapon(.handgun, ammo: [.handgunAmmo], capacity: 17, rateOfFire: 350),  // Semi-auto rate (~0.17s between shots)
    name: usesRealGunNames ? "Glock 17" : "G17",
    description: "Compact 9mm pistol with selective fire capability.",
  )

  static let glock18 = Item(
    id: "glock18c",
    kind: .weapon(.handgun, ammo: [.handgunAmmo], capacity: 19, rateOfFire: 1100),  // Full-auto capable (Glock 18 is select-fire)
    name: usesRealGunNames ? "Glock 18C" : "G18C",
    description: "Compact 9mm pistol with selective fire capability and an extended magazine.",
  )

  static let sigp320 = Item(
    id: "sigp320",
    kind: .weapon(.handgun, ammo: [.handgunAmmo], capacity: 17, rateOfFire: 240),  // Slower, more deliberate semi-auto
    name: usesRealGunNames ? "SIG Sauer P320" : "P320",
    description: "Modern striker-fired pistol with a modular design. Uses 9mm ammunition.",
  )

  static let beretta92 = Item(
    id: "beretta92",
    kind: .weapon(.handgun, ammo: [.handgunAmmo], capacity: 15, rateOfFire: 350),  // Semi-auto
    name: usesRealGunNames ? "Beretta 92" : "B92",
    description: "A compact 9mm pistol.",
  )

  static let fnx45 = Item(
    id: "fnx45",
    kind: .weapon(.handgun, ammo: [.handgunAmmo], capacity: 15, rateOfFire: 350),  // Semi-auto
    name: usesRealGunNames ? "FNX-45 Tactical" : "F45",
    description: "Compact, reliable, and affordable 9mm pistol.",
  )

  // MARK: - Shotguns

  static let remington870 = Item(
    id: "remington870",
    kind: .weapon(.shotgun, ammo: [.handgunAmmo], capacity: 8, rateOfFire: 60),  // Pump action, slow
    name: usesRealGunNames ? "Remington 870" : "R870",
    description: "Classic 12-gauge shotgun with a wooden frame.",
    requiresWideSlot: true,
  )

  static let spas12 = Item(
    id: "spas12",
    kind: .weapon(.shotgun, ammo: [.handgunAmmo], capacity: 8, rateOfFire: 120),  // Semi-auto, faster
    name: usesRealGunNames ? "SPAS-12" : "S-12",
    description: "A sporting shotgun with a 12-gauge barrel.",
    requiresWideSlot: true
  )

  // MARK: - SMGs

  static let mp5sd = Item(
    id: "mp5sd",
    kind: .weapon(.automatic, ammo: [.handgunAmmo], capacity: 30, rateOfFire: 800),  // 800 RPM typical
    name: usesRealGunNames ? "MP5SD" : "M5SD",
    description: "Submachine gun with a high rate of fire and built-in suppressor.",
    inspectionDistance: 0.46,
    requiresWideSlot: true,
  )

  // MARK: - Launchers

  static let m32 = Item(
    id: "m32",
    kind: .weapon(.launcher, ammo: [.grenadeRounds], capacity: 6, rateOfFire: 30),  // Very slow
    name: usesRealGunNames ? "M32" : "Y2",
    description: "A grenade launcher capable of launching several high-explosive grenades.",
    inspectionDistance: 0.46,
    requiresWideSlot: true,
  )

  // MARK: - Ammo

  static let handgunAmmo = Item(
    id: "handgun_ammo",
    kind: .ammo,
    name: "9mm Ammunition",
    description: "Standard 9 millimeter rounds for handguns.",
  )

  static let grenadeRounds = Item(
    id: "grenade_rounds",
    kind: .ammo,
    name: "40mm Grenades",
    description: "High-explosive 40 millimeter rounds for grenade launchers.",
    inspectionDistance: 0.05
  )

  // MARK: - Keys

  static let utilityKey = Item(
    id: "utility_key",
    name: "Utility Key",
    //realName: "Generator Key",
    description: "A generic key for utility cabinets.",
  )

  static let metroKey = Item(
    id: "metro_key",
    name: "Metro Key",
    description: "A rusty key attached to a Metro logo keychain.",
    inspectionDistance: 0.4
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

  static let catStatue = Item(
    id: "cat_statue",
    name: "Cat Statue",
    description: "A concrete statue of a cat. Cuuute! ^-^",
    inspectionDistance: 0.4,
  )
}
