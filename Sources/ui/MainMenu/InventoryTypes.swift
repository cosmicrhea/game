enum ItemType {
  case weapon
  case ammo
  case recovery
  case key
}

extension Item {
  static let knife = Item(
    id: "knife",
    name: "Military Knife",
    description: "This weapon is a veteran survivor’s first choice.",
  )

  static let glock17 = Item(
    id: "glock17",
    name: "Glock 17",
    description: "Compact 9mm pistol with selective fire capability.",
  )

  static let glock18 = Item(
    id: "glock18c",
    name: "Glock 18C",
    description: "Compact 9mm pistol with selective fire capability.",
  )

  static let p320 = Item(
    id: "sigp320",
    name: "SIG Sauer P320",
    description: "Modern striker-fired pistol with modular design.",
  )

  static let handgunAmmo = Item(
    id: "handgun_ammo",
    name: "9mm Ammunition",
    description: "Standard 9 millimeter rounds for handguns.",
  )

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

  static let allItems = [
    Item.knife,
    Item.glock17,
    Item.glock18,
    Item.p320,
    Item.handgunAmmo,
    //Item.lighter,
    Item.utilityKey,
    Item.metroKey,
//    Item.tagKey,
    Item.cryoGloves,
  ]
}

/// Represents an item that can be stored in inventory slots
public struct Item: Sendable {
  public let id: String
  public let name: String
  public let image: Image?
  public let description: String?
  public let modelPath: String?

  public init(id: String, name: String, image: Image? = nil, description: String? = nil, modelPath: String? = nil) {
    self.id = id
    self.name = name
    self.image = image ?? Image("Items/Weapons/\(id).png")
    self.description = description
    self.modelPath = modelPath ?? "Items/Weapons/\(id)"
  }
}

/// Represents the data for a single slot in a SlotGrid
public struct SlotData: Sendable {
  public let item: Item?
  public let quantity: Int?

  public init(item: Item? = nil, quantity: Int? = nil) {
    self.item = item
    self.quantity = quantity
  }

  /// Returns true if the slot is empty
  public var isEmpty: Bool {
    return item == nil
  }

  /// Returns true if the slot contains an item
  public var hasItem: Bool {
    return item != nil
  }

  /// Returns true if the slot should display a quantity number
  public var shouldShowQuantity: Bool {
    return quantity != nil
  }
}
