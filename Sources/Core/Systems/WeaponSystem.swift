import CJolt
import Foundation
import Jolt

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
  private weak var physicsWorld: PhysicsWorld?
  private weak var enemySystem: EnemySystem?
  private weak var cameraSystem: CameraSystem?
  private weak var playerController: PlayerController?

  // Debug visualization
  private var lastRayOrigin: RVec3?
  private var lastRayDirection: Vec3?
  private var lastRayRange: Float?

  /// Get last ray info for debug visualization
  func getLastRayInfo() -> (origin: RVec3, direction: Vec3, range: Float)? {
    guard let origin = lastRayOrigin,
      let direction = lastRayDirection,
      let range = lastRayRange
    else { return nil }
    return (origin, direction, range)
  }

  public init(
    inventory: Inventory? = nil,
    slotGrid: ItemSlotGrid? = nil,
    physicsWorld: PhysicsWorld? = nil,
    enemySystem: EnemySystem? = nil,
    cameraSystem: CameraSystem? = nil,
    playerController: PlayerController? = nil
  ) {
    self.inventory = inventory
    self.slotGrid = slotGrid
    self.physicsWorld = physicsWorld
    self.enemySystem = enemySystem
    self.cameraSystem = cameraSystem
    self.playerController = playerController
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
      // Deal melee damage
      dealMeleeDamage()
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

    // Deal damage based on weapon type
    switch item.weaponKind {
    case .handgun, .shotgun, .automatic:
      dealGunDamage()
    case .launcher:
      // TODO: Launch projectile for launchers
      dealGunDamage()  // Temporary: use raycast for now
    case .melee:
      break  // Already handled above
    case .none:
      break  // Not a weapon
    }

    // Reset attack timer
    timeSinceLastAttack = 0.0

    logger.trace("🔫 WeaponSystem: Fired successfully")
    return true
  }

  // MARK: - Damage Dealing

  private func dealGunDamage() {
    guard let physicsWorld = physicsWorld,
      let enemySystem = enemySystem,
      let cameraSystem = cameraSystem
    else { return }

    // Get camera forward direction from camera world transform
    let cameraWorldTransform = cameraSystem.cameraWorldTransform
    let cameraPosition = vec3(cameraWorldTransform[3].x, cameraWorldTransform[3].y, cameraWorldTransform[3].z)

    // Extract forward direction from camera transform (negative Z column)
    let forward = vec3(-cameraWorldTransform[2].x, -cameraWorldTransform[2].y, -cameraWorldTransform[2].z)
    let normalizedForward = normalize(forward)

    // Cast ray from camera position
    let rayOrigin = RVec3(x: cameraPosition.x, y: cameraPosition.y, z: cameraPosition.z)
    let rayDirection = Vec3(x: normalizedForward.x, y: normalizedForward.y, z: normalizedForward.z)
    let maxRange: Float = 50.0

    // Store ray info for debug visualization
    self.lastRayOrigin = rayOrigin
    self.lastRayDirection = rayDirection
    self.lastRayRange = maxRange

    // First, manually check if ray intersects any enemy's capsule
    // Character controllers might not be directly raycastable
    var closestEnemy: Enemy?
    var closestDistance: Float = Float.greatestFiniteMagnitude

    for enemy in enemySystem.aliveEnemies {
      guard let characterController = enemy.characterController else { continue }

      // Get enemy position and capsule dimensions
      let enemyPos = characterController.position
      let enemyPosition = vec3(enemyPos.x, enemyPos.y, enemyPos.z)

      // Determine capsule size based on enemy type
      let (capsuleHalfHeight, capsuleRadius): (Float, Float)
      if enemy is DogEnemy {
        capsuleHalfHeight = 0.4
        capsuleRadius = 0.25
      } else {
        capsuleHalfHeight = 0.8
        capsuleRadius = 0.4
      }

      // Check ray-capsule intersection manually
      let rayStart = vec3(rayOrigin.x, rayOrigin.y, rayOrigin.z)
      //let rayEnd = rayStart + normalizedForward * maxRange

      // Capsule is centered at enemy position, extends from -halfHeight to +halfHeight in Y
      let capsuleBottom = vec3(enemyPosition.x, enemyPosition.y - capsuleHalfHeight, enemyPosition.z)
      let capsuleTop = vec3(enemyPosition.x, enemyPosition.y + capsuleHalfHeight, enemyPosition.z)

      // Simple ray-capsule intersection test
      if let intersection = rayCapsuleIntersection(
        rayStart: rayStart,
        rayDir: normalizedForward,
        capsuleBottom: capsuleBottom,
        capsuleTop: capsuleTop,
        capsuleRadius: capsuleRadius
      ) {
        let distance = length(intersection - rayStart)
        if distance < closestDistance {
          closestDistance = distance
          closestEnemy = enemy
        }
      }
    }

    // If we found an enemy, deal damage
    if let enemy = closestEnemy {
      let damage: Float = 25.0  // Default damage
      enemy.takeDamage(damage)
      logger.debug(
        "🔫 Hit enemy \(enemy.id.uuidString.prefix(4)) for \(damage) damage (HP: \(enemy.health)/\(enemy.maxHealth))")
    } else {
      // Also check raycast for other objects (walls, etc.) for debug
      if let hit = physicsWorld.getPhysicsSystem().castRaySingle(origin: rayOrigin, direction: rayDirection) {
        logger.trace("🔫 Raycast hit body ID: \(hit.bodyID), fraction: \(hit.fraction)")
      } else {
        logger.trace("🔫 Raycast hit nothing")
      }
    }
  }

  // Helper function for ray-capsule intersection
  private func rayCapsuleIntersection(
    rayStart: vec3,
    rayDir: vec3,
    capsuleBottom: vec3,
    capsuleTop: vec3,
    capsuleRadius: Float
  ) -> vec3? {
    // Vector from bottom to top of capsule
    let capsuleAxis = capsuleTop - capsuleBottom
    let capsuleLength = length(capsuleAxis)
    guard capsuleLength > 0.0001 else { return nil }

    let capsuleDir = normalize(capsuleAxis)

    // Vector from ray start to capsule bottom
    let toCapsule = capsuleBottom - rayStart

    // Project ray direction onto capsule axis
    let rayDotAxis = dot(rayDir, capsuleDir)
    let toCapsuleDotAxis = dot(toCapsule, capsuleDir)

    // Closest point on ray to capsule axis
    let t = toCapsuleDotAxis / rayDotAxis
    guard t > 0 else { return nil }  // Ray is behind us

    let closestPointOnRay = rayStart + rayDir * t

    // Closest point on capsule axis to the ray point
    let distAlongAxis = dot(closestPointOnRay - capsuleBottom, capsuleDir)
    let clampedDist = max(0, min(capsuleLength, distAlongAxis))
    let capsulePoint = capsuleBottom + capsuleDir * clampedDist

    // Distance from ray to capsule axis
    let distToAxis = length(closestPointOnRay - capsulePoint)

    if distToAxis <= capsuleRadius {
      // Ray intersects capsule
      return closestPointOnRay
    }

    return nil
  }

  private func dealMeleeDamage() {
    guard let physicsWorld = physicsWorld,
      let enemySystem = enemySystem,
      let playerController = playerController
    else { return }

    let playerPosition = playerController.position
    let playerRotation = playerController.rotation

    // Calculate forward direction from player rotation
    let forwardX = sin(playerRotation)
    let forwardZ = cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)
    let normalizedForward = normalize(forward)

    // Melee range
    let meleeRange: Float = 1.5
    let meleeWidth: Float = 0.5
    let meleeHeight: Float = 1.0

    // Create a box shape for melee attack
    let boxHalfExtents = Vec3(x: meleeWidth * 0.5, y: meleeHeight * 0.5, z: meleeRange * 0.5)
    let boxShape = BoxShape(halfExtent: boxHalfExtents)

    // Position box in front of player
    let boxCenter = playerPosition + normalizedForward * (meleeRange * 0.5)
    var baseOffset = RVec3(x: boxCenter.x, y: boxCenter.y, z: boxCenter.z)

    // Create rotation matrix for the box (aligned with forward direction)
    let up = vec3(0, 1, 0)
    let right = normalize(cross(up, normalizedForward))
    let correctedUp = normalize(cross(normalizedForward, right))

    // Build rotation matrix (right, up, forward)
    var boxTransform = JPH_RMat4()
    boxTransform.column.0 = JPH_Vec4(x: right.x, y: right.y, z: right.z, w: 0)
    boxTransform.column.1 = JPH_Vec4(x: correctedUp.x, y: correctedUp.y, z: correctedUp.z, w: 0)
    boxTransform.column.2 = JPH_Vec4(x: normalizedForward.x, y: normalizedForward.y, z: normalizedForward.z, w: 0)
    boxTransform.column.3 = JPH_Vec4(x: 0, y: 0, z: 0, w: 1)

    // Check what's colliding with the melee box (not casting, just checking overlap)
    let results = physicsWorld.getPhysicsSystem().collideShapeAll(
      shape: boxShape,
      scale: Vec3(x: 1, y: 1, z: 1),
      centerOfMassTransform: boxTransform,
      baseOffset: &baseOffset
    )

    // Check all hits for enemies
    for result in results {
      // Create a fake RayHit for the enemy lookup (we only need bodyID)
      let fakeHit = JPH_RayCastResult(bodyID: result.bodyID2, fraction: 0, subShapeID2: 0)
      if let enemy = enemySystem.findEnemy(hitByRaycast: RayHit(fakeHit), in: physicsWorld) {
        // Deal melee damage
        let damage: Float = 50.0  // Melee does more damage
        enemy.takeDamage(damage)
        logger.debug(
          "🔪 Melee hit enemy \(enemy.id.uuidString.prefix(4)) for \(damage) damage (HP: \(enemy.health)/\(enemy.maxHealth))"
        )
      }
    }
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
