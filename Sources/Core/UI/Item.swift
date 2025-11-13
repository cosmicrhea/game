public enum WeaponKind: String, Sendable {
  case melee
  case handgun
  case shotgun
  case automatic
  case launcher
}

public enum ItemKind: Sendable {
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
public struct Item: Sendable {
  public let id: String
  public let kind: ItemKind
  public let name: String
  public let image: Image?
  public let description: String?
  public let modelPath: String?
  public let inspectionDistance: Float
  public let requiresWideSlot: Bool
  public let wideImage: Image?

  public init(
    id: String,
    kind: ItemKind = .key,
    name: String,
    image: Image? = nil,
    description: String? = nil,
    modelPath: String? = nil,
    inspectionDistance: Float? = nil,
    requiresWideSlot: Bool = false,
    wideImage: Image? = nil
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.image = image ?? Image("Items/Weapons/\(id).png")
    self.description = description
    self.modelPath = modelPath ?? "Items/Weapons/\(id)"
    self.inspectionDistance = inspectionDistance ?? (requiresWideSlot == true ? 0.69 : 0.23)
    self.requiresWideSlot = requiresWideSlot
    self.wideImage = requiresWideSlot ? wideImage ?? Image("Items/Weapons/\(id)_wide.png") : wideImage
  }

  // MARK: - Convenience Properties

  /// Get weapon kind if this is a weapon
  public var weaponKind: WeaponKind? {
    return kind.weaponKind
  }
}
