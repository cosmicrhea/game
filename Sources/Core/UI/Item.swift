public enum WeaponKind: String, Sendable {
  case melee
  case handgun
  case shotgun
  case automatic
  case launcher
}

public enum ItemKind: Sendable, Hashable {
  case key
  case weapon(WeaponKind, ammo: [Item] = [], capacity: Int? = nil, rateOfFire: Float? = nil)
  case ammo
  case recovery

  /// Helper to check if this is a weapon kind
  public var isWeapon: Bool {
    if case .weapon = self { return true }
    return false
  }

  /// Get weapon kind if this is a weapon
  public var weaponKind: WeaponKind? {
    if case .weapon(let kind, _, _, _) = self { return kind }
    return nil
  }

  /// Get compatible ammo types for this weapon
  public var compatibleAmmo: [Item] {
    if case .weapon(_, let ammo, _, _) = self { return ammo }
    return []
  }

  /// Get weapon capacity (magazine size)
  public var weaponCapacity: Int? {
    if case .weapon(_, _, let capacity, _) = self { return capacity }
    return nil
  }

  /// Get weapon rate of fire (rounds per minute)
  public var weaponRateOfFire: Float? {
    if case .weapon(_, _, _, let rateOfFire) = self { return rateOfFire }
    return nil
  }

  /// Get time between attacks in seconds (calculated from rate of fire)
  public var weaponTimeBetweenAttacks: Float? {
    guard let rateOfFire = weaponRateOfFire, rateOfFire > 0 else { return nil }
    return 60.0 / rateOfFire
  }
}

/// Represents an item that can be stored in inventory slots
public struct Item: Sendable, Hashable {
  public let id: String
  public let kind: ItemKind
  public let name: String
  public let description: String?
  public let image: Image?
  public let modelPath: String?
  public let inspectionDistance: Float
  public let inspectionYaw: Float?
  public let inspectionPitch: Float?
  public let requiresWideSlot: Bool
  public let wideImage: Image?
  /// Dictionary mapping other item IDs to result items when combined with this item
  /// Uses string IDs for keys to avoid circular reference issues during initialization
  public let combinations: [String: Item]

  public init(
    id: String,
    kind: ItemKind = .key,
    name: String,
    description: String? = nil,
    image: Image? = nil,
    modelPath: String? = nil,
    inspectionDistance: Float? = nil,
    inspectionYaw: Float? = nil,
    inspectionPitch: Float? = nil,
    requiresWideSlot: Bool = false,
    wideImage: Image? = nil,
    combinations: [String: Item] = [:]
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.description = description
    self.image = image ?? Image("Items/Weapons/\(id).png")
    self.modelPath = modelPath ?? "Items/Weapons/\(id)"
    self.inspectionDistance = inspectionDistance ?? (requiresWideSlot == true ? 0.69 : 0.23)
    self.inspectionYaw = inspectionYaw
    self.inspectionPitch = inspectionPitch
    self.requiresWideSlot = requiresWideSlot
    self.wideImage = requiresWideSlot ? wideImage ?? Image("Items/Weapons/\(id)_wide.png") : wideImage
    self.combinations = combinations
  }

  // MARK: - Convenience Properties

  /// Get weapon kind if this is a weapon
  public var weaponKind: WeaponKind? {
    return kind.weaponKind
  }

  /// Check if this item can combine with another item, and return the result item if so
  /// Checks combinations bidirectionally (both items' combination dictionaries)
  public func canCombine(with other: Item) -> Item? {
    // Check if this item has a combination with the other item
    if let resultItem = combinations[other.id] {
      return resultItem
    }
    // Check if the other item has a combination with this item (bidirectional)
    if let resultItem = other.combinations[id] {
      return resultItem
    }
    return nil
  }
}

// MARK: - Hashable Conformance

extension Item {
  public func hash(into hasher: inout Hasher) {
    // Use id for hashing (Images are excluded)
    hasher.combine(id)
  }

  public static func == (lhs: Item, rhs: Item) -> Bool {
    // Compare by id (Images are excluded)
    return lhs.id == rhs.id
  }
}
