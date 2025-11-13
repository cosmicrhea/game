/// Manages weapon aiming, firing, and reloading
@MainActor
public final class WeaponSystem {
  /// Aim state for weapons
  public enum AimState: Sendable {
    case idle
    case readyAim  // First stage of aiming
    case aiming  // Full aim state
  }

  // MARK: - Configuration
  /// Whether aiming uses toggle mode (true) or hold mode (false)
  public var usesToggledAiming: Bool = false

  // MARK: - State
  public private(set) var aimState: AimState = .idle

  /// Public access to aim state for checking in update loop
  public var currentAimState: AimState {
    return aimState
  }

  /// Maps weapon slot index to currently loaded ammo type
  private var loadedAmmoTypes: [Int: Item] = [:]

  /// Time since last attack (for rate of fire limiting)
  private var timeSinceLastAttack: Float = 0.0

  // MARK: - References
  private weak var inventory: Inventory?
  private weak var slotGrid: ItemSlotGrid?

  public init(inventory: Inventory? = nil, slotGrid: ItemSlotGrid? = nil) {
    self.inventory = inventory
    self.slotGrid = slotGrid
  }

  // MARK: - Aim State Management

  /// Enter ready aim state (first stage)
  public func enterReadyAim() {
    guard aimState == .idle else { return }
    aimState = .readyAim
    logger.trace("🔫 WeaponSystem: Entered ready aim state")
  }

  /// Enter full aim state (second stage)
  public func enterAim() {
    guard aimState == .readyAim else { return }
    aimState = .aiming
    logger.trace("🔫 WeaponSystem: Entered aiming state")
  }

  /// Exit aim mode
  public func exitAim() {
    aimState = .idle
    logger.trace("🔫 WeaponSystem: Exited aim mode")
  }

  /// Toggle aim state (for toggle mode)
  public func toggleAim() {
    switch aimState {
    case .idle:
      enterReadyAim()
    case .readyAim:
      enterAim()
    case .aiming:
      exitAim()
    }
  }

  /// Check if currently aiming
  public var isAiming: Bool {
    return aimState == .aiming
  }

  /// Check if in ready aim state
  public var isReadyAim: Bool {
    return aimState == .readyAim
  }

  // MARK: - Weapon Operations

  /// Update weapon system (call each frame with deltaTime)
  public func update(deltaTime: Float) {
    timeSinceLastAttack += deltaTime
  }

  /// Fire the equipped weapon
  public func fire() -> Bool {
    guard aimState == .aiming else {
      logger.warning("🔫 WeaponSystem: Cannot fire - not aiming (state: \(aimState))")
      return false
    }
    guard let slotGrid = slotGrid else {
      logger.warning("🔫 WeaponSystem: Cannot fire - no slotGrid")
      return false
    }
    guard let equippedIndex = slotGrid.equippedWeaponIndex else {
      logger.warning("🔫 WeaponSystem: Cannot fire - no weapon equipped")
      return false
    }
    guard let slotData = slotGrid.getSlotData(at: equippedIndex),
      let item = slotData.item,
      item.kind.isWeapon
    else {
      logger.warning("🔫 WeaponSystem: Cannot fire - invalid weapon slot data")
      return false
    }

    // Check rate of fire
    let timeBetweenAttacks: Float
    if let weaponTimeBetweenAttacks = item.kind.weaponTimeBetweenAttacks {
      timeBetweenAttacks = weaponTimeBetweenAttacks
    } else {
      // Default rate of fire for weapons without specified rate
      // Melee weapons: ~40 RPM (1.5s between attacks) - slower, more deliberate
      // Other weapons: use handgun default ~350 RPM
      if item.weaponKind == .melee {
        timeBetweenAttacks = 1.5  // 40 RPM for melee - slower, more deliberate
      } else {
        timeBetweenAttacks = 60.0 / 350.0  // Default handgun rate
      }
    }

    if timeSinceLastAttack < timeBetweenAttacks {
      // Not enough time has passed since last attack
      return false
    }

    logger.trace("🔫 WeaponSystem: Firing \(item.name)")

    // Handle melee weapons (no ammo)
    if item.weaponKind == .melee {
      // Melee attack - no ammo consumption
      logger.trace("🔫 WeaponSystem: Melee attack - no ammo consumed")
      UISound.knifeSlash()
      // Reset attack timer
      timeSinceLastAttack = 0.0
      return true
    }

    // Handle ammo-based weapons
    guard case .weapon(_, let compatibleAmmo, _, _) = item.kind,
      !compatibleAmmo.isEmpty
    else {
      return false
    }

    // Check if weapon has ammo loaded
    let currentAmmo = slotData.quantity ?? 0
    logger.trace("🔫 WeaponSystem: Current ammo: \(currentAmmo)")
    guard currentAmmo > 0 else {
      // Weapon is empty - play empty sound based on weapon type
      switch item.weaponKind {
      case .handgun:
        UISound.handgunEmpty()
      case .shotgun:
        UISound.shotgunEmpty()
      case .launcher:
        UISound.launcherEmpty()
      default:
        break
      }
      // Auto-reload if empty
      logger.trace("🔫 WeaponSystem: Weapon empty, attempting reload...")
      return reload()
    }

    // Consume one round (keep same ammo type)
    let newAmmo = currentAmmo - 1
    logger.trace("🔫 WeaponSystem: Consuming ammo: \(currentAmmo) -> \(newAmmo)")
    let updatedSlotData = ItemSlotData(
      item: item,
      quantity: newAmmo
    )
    slotGrid.setSlotData(updatedSlotData, at: equippedIndex)

    // Play fire sound based on weapon type
    switch item.weaponKind {
    case .handgun:
      UISound.handgunFire()
    case .shotgun:
      UISound.shotgunFire()
    case .launcher:
      UISound.launcherFire()
    default:
      break
    }

    // Auto-reload if empty after firing
    if newAmmo == 0 {
      logger.trace("🔫 WeaponSystem: Weapon empty after firing, reloading...")
      _ = reload()
    }

    // Reset attack timer
    timeSinceLastAttack = 0.0

    logger.trace("🔫 WeaponSystem: Fired successfully")
    return true
  }

  /// Reload the equipped weapon
  public func reload() -> Bool {
    logger.trace("🔫 WeaponSystem: Attempting reload...")
    guard let slotGrid = slotGrid else {
      logger.warning("🔫 WeaponSystem: Reload failed - no slotGrid")
      return false
    }
    guard let equippedIndex = slotGrid.equippedWeaponIndex else {
      logger.warning("🔫 WeaponSystem: Reload failed - no weapon equipped")
      return false
    }
    guard let slotData = slotGrid.getSlotData(at: equippedIndex),
      let item = slotData.item,
      case .weapon(_, let compatibleAmmo, let capacity, _) = item.kind,
      !compatibleAmmo.isEmpty,
      let capacity = capacity
    else {
      logger.warning("🔫 WeaponSystem: Reload failed - invalid weapon or no compatible ammo")
      return false
    }

    logger.trace(
      "🔫 WeaponSystem: Reloading \(item.name) (capacity: \(capacity), compatible ammo: \(compatibleAmmo.map { $0.id }))"
    )

    // Find compatible ammo in inventory
    guard let inventory else { return false }

    // Prefer currently loaded ammo type if available
    let ammoPriority: [Item]
    if let currentAmmoType = loadedAmmoTypes[equippedIndex],
      compatibleAmmo.contains(where: { $0.id == currentAmmoType.id })
    {
      // Put current ammo type first
      ammoPriority = [currentAmmoType] + compatibleAmmo.filter { $0.id != currentAmmoType.id }
    } else {
      // Use compatible ammo in order
      ammoPriority = compatibleAmmo
    }

    for ammoItem in ammoPriority {
      // Find ammo slot
      for (index, inventorySlot) in inventory.slots.enumerated() {
        guard let inventorySlot = inventorySlot,
          let inventoryItem = inventorySlot.item,
          inventoryItem.id == ammoItem.id,
          let ammoQuantity = inventorySlot.quantity,
          ammoQuantity > 0
        else { continue }

        // Calculate how much ammo we need
        let currentAmmo = slotData.quantity ?? 0
        let needed = capacity - currentAmmo
        guard needed > 0 else { return true }  // Already full

        // Take ammo from inventory
        let toTake = min(needed, ammoQuantity)
        let newAmmoQuantity = ammoQuantity - toTake
        let newLoadedAmmo = currentAmmo + toTake

        // Update weapon slot with new ammo count
        let updatedWeaponSlot = ItemSlotData(
          item: item,
          quantity: newLoadedAmmo
        )
        slotGrid.setSlotData(updatedWeaponSlot, at: equippedIndex)

        // Track the loaded ammo type
        loadedAmmoTypes[equippedIndex] = ammoItem

        logger.trace("🔫 WeaponSystem: Reloaded \(toTake) rounds (now: \(newLoadedAmmo)/\(capacity))")

        // Play reload sound based on weapon type
        switch item.weaponKind {
        case .handgun:
          UISound.handgunReload()
        case .shotgun:
          UISound.shotgunReload()
        case .launcher:
          UISound.launcherReload()
        default:
          break
        }

        // Update ammo slot
        if newAmmoQuantity > 0 {
          let updatedAmmoSlot = ItemSlotData(
            item: inventoryItem,
            quantity: newAmmoQuantity
          )
          inventory.slots[index] = updatedAmmoSlot
        } else {
          // Remove ammo slot if empty
          inventory.slots[index] = nil
        }

        logger.trace("🔫 WeaponSystem: Reload successful")
        return true
      }
    }

    logger.warning("🔫 WeaponSystem: Reload failed - no compatible ammo found in inventory")
    return false  // No compatible ammo found
  }

  /// Clear loaded ammo type when weapon is unequipped or moved
  public func clearLoadedAmmoType(for slotIndex: Int) {
    loadedAmmoTypes.removeValue(forKey: slotIndex)
  }

  /// Get the currently loaded ammo type for a weapon slot
  public func getLoadedAmmoType(for slotIndex: Int) -> Item? {
    return loadedAmmoTypes[slotIndex]
  }
}
