import GL
import GLMath

extension Item {
  static let allItems = [
    Item(
      id: "knife",
      name: "Military Knife",
      image: Image("Items/Weapons/knife.png"),
      description: "This weapon is a veteran survivor’s first choice.",
      modelPath: "Items/Weapons/knife"
    ),
    Item(
      id: "glock18c",
      name: "Glock 18C",
      image: Image("Items/Weapons/glock18c~2.png"),
      description: "Compact 9mm pistol with selective fire capability.",
      modelPath: "Items/Weapons/glock18c"
    ),
    Item(
      id: "sigp320",
      name: "SIG Sauer P320",
      image: Image("Items/Weapons/sigp320.png"),
      description: "Modern striker-fired pistol with modular design.",
      modelPath: "Items/Weapons/sigp320"
    ),
//    Item(
//      id: "handgun_ammo",
//      name: "9mm Ammunition",
//      image: Image("Items/Weapons/handgun_ammo.png"),
//      description: "Standard 9 millimeter rounds for handguns.",
//      //modelPath: "Items/Weapons/handgun_ammo"
//    ),
    Item(
      id: "lighter",
      name: "Lighter",
      image: Image("Items/Weapons/lighter.png"),
      description: "Simple butane lighter for lighting fires.",
      modelPath: "Items/Weapons/lighter"
    ),
    Item(
      id: "utility_key",
      name: "Utility Key",
      image: Image("Items/Weapons/utility_key.png"),
      description: "A key for utility cabinets.",
      modelPath: "Items/Weapons/utility_key"
    ),
    Item(
      id: "metro_key",
      name: "Metro Key",
      image: Image("Items/Weapons/metro_key.png"),
      description: "A rusty key attached to a Metro logo keychain.",
      modelPath: "Items/Weapons/metro_key"
    ),
    Item(
      id: "tag_key",
      name: "Key with Tag",
      image: Image("Items/Weapons/tag_key.png"),
      description: "A key with a blank tag. Odd.",
      modelPath: "Items/Weapons/tag_key"
    ),
    Item(
      id: "cryo_gloves",
      name: "Cryogenic Gloves",
      image: Image("Items/Weapons/cryo_gloves.png"),
      description: "A pair of gloves suitable for handling supercooled liquids.",
      modelPath: "Items/Weapons/cryo_gloves"
    ),
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
    self.image = image
    self.description = description
    self.modelPath = modelPath
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
