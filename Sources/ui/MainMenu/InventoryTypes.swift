public enum ItemKind: String, Sendable {
  case key
  case weapon
  case ammo
  case recovery
}

/// Represents an item that can be stored in inventory slots
public struct Item: Sendable {
  public let id: String
  public let kind: ItemKind
  public let name: String
  public let image: Image?
  public let description: String?
  public let modelPath: String?

  public init(id: String, kind: ItemKind = .key, name: String, image: Image? = nil, description: String? = nil, modelPath: String? = nil) {
    self.id = id
    self.kind = kind
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
