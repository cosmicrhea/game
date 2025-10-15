import GL
import GLMath

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
