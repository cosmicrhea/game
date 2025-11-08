/// Represents the data for a single slot in an ItemSlotGrid
public struct ItemSlotData: Sendable {
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
