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
    id: String,
    kind: ItemKind = .key,
    name: String,
    image: Image? = nil,
    description: String? = nil,
    modelPath: String? = nil,
    inspectionDistance: Float = 0.23
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
