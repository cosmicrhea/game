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
  public let inspectionDistance: Float

  public init(
    id: String, kind: ItemKind = .key, name: String, image: Image? = nil, description: String? = nil,
    modelPath: String? = nil, inspectionDistance: Float = 0.3
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.image = image ?? Image("Items/Weapons/\(id).png")
    self.description = description
    self.modelPath = modelPath ?? "Items/Weapons/\(id)"
    self.inspectionDistance = inspectionDistance
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

/// Inventory container - a box for an array of slots
@MainActor
public final class Inventory {
  public var slots: [SlotData?]

  public init(slots: [SlotData?]) {
    self.slots = slots
  }

  /// Global player 1 inventory
  private nonisolated(unsafe) static var _player1: Inventory? = nil

  public static var player1: Inventory {
    if _player1 == nil {
      _player1 = Inventory(slots: [
        SlotData(item: .knife, quantity: nil),
        SlotData(item: .glock17, quantity: 15),
        SlotData(item: .handgunAmmo, quantity: 69),
        SlotData(item: .sigp320, quantity: 0),
        SlotData(item: .morphine, quantity: nil),
        SlotData(item: .glock18, quantity: 17),
        SlotData(item: .metroKey, quantity: nil),
        SlotData(item: .utilityKey, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),
        SlotData(item: nil, quantity: nil),

        //        SlotData(item: .morphine, quantity: nil),
        //        SlotData(item: .knife, quantity: nil),
        //        SlotData(item: .glock17, quantity: 15),
        //        SlotData(item: .glock18, quantity: 17),
        //        SlotData(item: .sigp320, quantity: 0),
        //        SlotData(item: .fnx45, quantity: 15),
        //        SlotData(item: .handgunAmmo, quantity: 69),
        //        SlotData(item: .utilityKey, quantity: nil),
        //        SlotData(item: .metroKey, quantity: nil),
        //        SlotData(item: .cryoGloves, quantity: nil),
        //        SlotData(item: .lighter, quantity: nil),
        //        SlotData(item: .beretta92, quantity: 17),
        //        SlotData(item: .remington870, quantity: 8),
        //        SlotData(item: .spas12, quantity: 10),
        //        SlotData(item: .mp5sd, quantity: 30),
        //        SlotData(item: nil, quantity: nil),  // Empty slot

        // (.morphine, nil),
        // (.knife, nil),
        // (.glock17, 15),
        // (.glock18, 17),
        // (.sigp320, 0),
        // //      (.beretta92, 17),
        // (.fnx45, 15),
        // (.handgunAmmo, 69),
        // (.utilityKey, nil),
        // (.metroKey, nil),
        // //      (.tagKey, nil),
        // (.cryoGloves, nil),
        // (.lighter, nil),
        // //      (.remington870, 8),
        // //      (.spas12, 10),
        // //      (.mp5sd, 30),
      ])
    }

    return _player1!
  }
}
