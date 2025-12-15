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

  // MARK: - Projectiles
  /// Active projectiles (grenades, etc.)
  private var activeProjectiles: [Projectile] = []

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

    // Update projectiles
    updateProjectiles(deltaTime: deltaTime)
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
      launchProjectile()
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
      let playerController = playerController
    else { return }

    // Use player position and rotation (tank controls, not first-person)
    // Same calculation as melee damage - forward direction from player rotation
    let playerPosition = playerController.position
    let playerRotation = playerController.rotation

    // Calculate forward direction from player rotation
    let forwardX = sin(playerRotation)
    let forwardZ = cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)
    let normalizedForward = normalize(forward)

    // Cast ray from weapon height (chest level, not center of capsule)
    // Player capsule: halfHeight 0.8, radius 0.4, so center is at position.y
    // Weapon should be at chest height, roughly position.y + 0.3
    let weaponHeightOffset: Float = 0.3
    let weaponPosition = vec3(playerPosition.x, playerPosition.y + weaponHeightOffset, playerPosition.z)
    let rayOrigin = RVec3(x: weaponPosition.x, y: weaponPosition.y, z: weaponPosition.z)
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

    let rayStart = vec3(rayOrigin.x, rayOrigin.y, rayOrigin.z)
    let rayEnd = rayStart + normalizedForward * maxRange

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

      // Capsule is centered at enemy position, extends from -halfHeight to +halfHeight in Y
      // Check ray-capsule intersection using a more robust algorithm
      if let intersection = rayCapsuleIntersection(
        rayStart: rayStart,
        rayEnd: rayEnd,
        capsuleCenter: enemyPosition,
        capsuleHalfHeight: capsuleHalfHeight,
        capsuleRadius: capsuleRadius
      ) {
        let distance = length(intersection - rayStart)
        if distance < closestDistance && distance <= maxRange {
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
      // Debug: log ray info and enemy positions
      logger.debug("🔫 No enemy hit. Ray from \(rayStart) direction \(normalizedForward)")
      logger.debug("🔫 Checking \(enemySystem.aliveEnemies.count) enemies")
      for enemy in enemySystem.aliveEnemies.prefix(3) {
        if let charController = enemy.characterController {
          let enemyPos = vec3(charController.position.x, charController.position.y, charController.position.z)
          let distToEnemy = length(enemyPos - rayStart)
          logger.debug("🔫 Enemy at \(enemyPos), distance: \(distToEnemy)")
        }
      }

      // Also check raycast for other objects (walls, etc.) for debug
      if let hit = physicsWorld.getPhysicsSystem().castRaySingle(origin: rayOrigin, direction: rayDirection) {
        logger.debug("🔫 Raycast hit body ID: \(hit.bodyID), fraction: \(hit.fraction)")
      } else {
        logger.debug("🔫 Raycast hit nothing")
      }
    }
  }

  // Helper function for ray-capsule intersection
  // Uses a more robust algorithm that handles the cylinder and both sphere caps
  private func rayCapsuleIntersection(
    rayStart: vec3,
    rayEnd: vec3,
    capsuleCenter: vec3,
    capsuleHalfHeight: Float,
    capsuleRadius: Float
  ) -> vec3? {
    let rayDir = normalize(rayEnd - rayStart)
    let rayLength = length(rayEnd - rayStart)

    // Capsule axis is vertical (Y axis)
    let capsuleBottom = vec3(capsuleCenter.x, capsuleCenter.y - capsuleHalfHeight, capsuleCenter.z)
    let capsuleTop = vec3(capsuleCenter.x, capsuleCenter.y + capsuleHalfHeight, capsuleCenter.z)
    let capsuleAxis = capsuleTop - capsuleBottom
    let capsuleDir = normalize(capsuleAxis)

    // Calculate closest points between ray and capsule axis
    // Using the standard line-line distance formula
    let w = rayStart - capsuleBottom
    let a = dot(rayDir, rayDir)  // Should be 1.0 since rayDir is normalized
    let b = dot(rayDir, capsuleDir)
    let c = dot(capsuleDir, capsuleDir)  // Should be 1.0
    let d = dot(w, rayDir)
    let e = dot(w, capsuleDir)

    let denom = a * c - b * b
    guard abs(denom) > 0.0001 else {
      // Ray is parallel to capsule axis - check distance to axis
      let distToAxis = length(w - capsuleDir * dot(w, capsuleDir))
      if distToAxis <= capsuleRadius {
        // Check if within capsule height bounds
        let yDist = dot(w, capsuleDir)
        if yDist >= -capsuleHalfHeight && yDist <= capsuleHalfHeight {
          return rayStart  // Intersection at ray start
        }
      }
      return nil
    }

    // Calculate parameters for closest points
    let t = (b * e - c * d) / denom
    let s = (a * e - b * d) / denom

    // Clamp s to capsule bounds
    let sClamped = max(-capsuleHalfHeight, min(capsuleHalfHeight, s))

    // Closest point on capsule axis
    let capsulePoint = capsuleBottom + capsuleDir * (sClamped + capsuleHalfHeight)

    // Closest point on ray
    let rayPoint = rayStart + rayDir * t

    // Distance between closest points
    let dist = length(rayPoint - capsulePoint)

    // Check if ray intersects capsule
    if dist <= capsuleRadius && t >= 0 && t <= rayLength {
      // Return the intersection point on the ray
      return rayPoint
    }

    // Also check sphere caps (top and bottom)
    // Check bottom sphere
    let bottomSphereCenter = capsuleBottom
    if let bottomHit = raySphereIntersection(
      rayStart: rayStart,
      rayDir: rayDir,
      rayLength: rayLength,
      sphereCenter: bottomSphereCenter,
      sphereRadius: capsuleRadius
    ) {
      return bottomHit
    }

    // Check top sphere
    let topSphereCenter = capsuleTop
    if let topHit = raySphereIntersection(
      rayStart: rayStart,
      rayDir: rayDir,
      rayLength: rayLength,
      sphereCenter: topSphereCenter,
      sphereRadius: capsuleRadius
    ) {
      return topHit
    }

    return nil
  }

  // Helper for ray-sphere intersection (for capsule end caps)
  private func raySphereIntersection(
    rayStart: vec3,
    rayDir: vec3,
    rayLength: Float,
    sphereCenter: vec3,
    sphereRadius: Float
  ) -> vec3? {
    let toSphere = sphereCenter - rayStart
    let projectionLength = dot(toSphere, rayDir)

    // Ray doesn't point toward sphere
    guard projectionLength >= 0 && projectionLength <= rayLength else { return nil }

    let closestPoint = rayStart + rayDir * projectionLength
    let distToCenter = length(closestPoint - sphereCenter)

    if distToCenter <= sphereRadius {
      // Calculate actual intersection point (closest point on ray to sphere surface)
      // Use the point where the ray enters the sphere
      let halfChord = sqrt(sphereRadius * sphereRadius - distToCenter * distToCenter)
      let t = max(0, projectionLength - halfChord)
      if t <= rayLength {
        return rayStart + rayDir * t
      }
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
    // baseOffset should be zero since we're including position in the transform
    var baseOffset = RVec3(x: 0, y: 0, z: 0)

    // Create rotation matrix for the box (aligned with forward direction)
    let up = vec3(0, 1, 0)
    let right = normalize(cross(up, normalizedForward))
    let correctedUp = normalize(cross(normalizedForward, right))

    // Build rotation matrix (right, up, forward) with translation
    // Create RMat44 from column vectors (right, up, forward, position)
    let boxTransform = RMat44(
      right.x, correctedUp.x, normalizedForward.x, boxCenter.x,
      right.y, correctedUp.y, normalizedForward.y, boxCenter.y,
      right.z, correctedUp.z, normalizedForward.z, boxCenter.z,
      0, 0, 0, 1
    )

    // Check what's colliding with the melee box (not casting, just checking overlap)
    let results = physicsWorld.getPhysicsSystem().collideShapeAll(
      shape: boxShape,
      scale: Vec3(x: 1, y: 1, z: 1),
      centerOfMassTransform: boxTransform.cValue,
      baseOffset: &baseOffset
    )

    // Check all hits for enemies
    for result in results {
      // Create a RayHit for the enemy lookup (we only need bodyID)
      let fakeHit = RayHit(bodyID: result.bodyID2, fraction: 0)
      if let enemy = enemySystem.findEnemy(hitByRaycast: fakeHit, in: physicsWorld) {
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
        guard let inventoryItem = inventorySlot.item,
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
          // Clear ammo slot if empty
          inventory.slots[index] = ItemSlotData(item: nil, quantity: nil)
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

  // MARK: - Projectiles

  /// Projectile class for grenades and other launched projectiles
  private class Projectile {
    let bodyID: BodyID
    var lifetime: Float
    let explosionRadius: Float
    let explosionDamage: Float
    weak var physicsWorld: PhysicsWorld?
    weak var enemySystem: EnemySystem?

    init(
      bodyID: BodyID,
      lifetime: Float,
      explosionRadius: Float,
      explosionDamage: Float,
      physicsWorld: PhysicsWorld?,
      enemySystem: EnemySystem?
    ) {
      self.bodyID = bodyID
      self.lifetime = lifetime
      self.explosionRadius = explosionRadius
      self.explosionDamage = explosionDamage
      self.physicsWorld = physicsWorld
      self.enemySystem = enemySystem
    }

    func update(deltaTime: Float) -> Bool {
      // Decrease lifetime
      lifetime -= deltaTime
      return lifetime > 0
    }

    @MainActor
    func explode() {
      guard let physicsWorld = physicsWorld,
        let enemySystem = enemySystem
      else { return }

      // Get explosion position from physics body
      let bodyInterface = physicsWorld.bodyInterface()
      let position = bodyInterface.getCenterOfMassPosition(bodyID)
      let explosionPos = vec3(position.x, position.y, position.z)

      // Play explosion sound
      UISound.grenadeHit()

      // Deal damage to enemies in radius
      for enemy in enemySystem.aliveEnemies {
        guard let characterController = enemy.characterController else { continue }

        let enemyPos = characterController.position
        let enemyPosition = vec3(enemyPos.x, enemyPos.y, enemyPos.z)

        let distance = length(enemyPosition - explosionPos)
        if distance <= explosionRadius {
          // Deal damage (could scale by distance if desired)
          enemy.takeDamage(explosionDamage)
          let enemyHealth = enemy.health
          let enemyMaxHealth = enemy.maxHealth
          logger.debug(
            "💥 Explosion hit enemy \(enemy.id.uuidString.prefix(4)) for \(explosionDamage) damage (distance: \(distance), HP: \(enemyHealth)/\(enemyMaxHealth))"
          )
        }
      }

      // Remove physics body
      bodyInterface.removeAndDestroyBody(bodyID)
    }
  }

  /// Launch a projectile (grenade) from the weapon
  private func launchProjectile() {
    guard let physicsWorld = physicsWorld,
      let playerController = playerController
    else { return }

    // Get weapon position and direction (same as hitscan)
    let playerPosition = playerController.position
    let playerRotation = playerController.rotation

    // Calculate forward direction from player rotation
    let forwardX = sin(playerRotation)
    let forwardZ = cos(playerRotation)
    let forward = vec3(forwardX, 0, forwardZ)
    let normalizedForward = normalize(forward)

    // Weapon height offset (chest level)
    let weaponHeightOffset: Float = 0.3
    let weaponPosition = vec3(playerPosition.x, playerPosition.y + weaponHeightOffset, playerPosition.z)

    // Create projectile physics body
    let projectileRadius: Float = 0.05  // Small grenade
    let sphereShape = SphereShape(radius: projectileRadius)

    // Initial velocity: forward + slight upward arc
    let launchSpeed: Float = 15.0  // m/s
    let upwardBias: Float = 0.15  // Slight arc
    let initialVelocityVec3 = normalizedForward * launchSpeed + vec3(0, upwardBias * launchSpeed, 0)
    let initialVelocity = Vec3(x: initialVelocityVec3.x, y: initialVelocityVec3.y, z: initialVelocityVec3.z)

    // Create body settings
    let bodySettings = BodyCreationSettings(
      shape: sphereShape,
      position: RVec3(x: weaponPosition.x, y: weaponPosition.y, z: weaponPosition.z),
      rotation: Quat.identity,
      motionType: .dynamic,
      objectLayer: 0  // Use collision layer
    )

    // Set initial velocity (need to set after creation)
    let bodyInterface = physicsWorld.bodyInterface()
    let bodyID = bodyInterface.createAndAddBody(settings: bodySettings, activation: .activate)
    if bodyID != 0 {
      bodyInterface.setLinearVelocity(bodyID, initialVelocity)

      // Create projectile instance
      let projectile = Projectile(
        bodyID: bodyID,
        lifetime: 5.0,  // 5 second max lifetime
        explosionRadius: 3.0,  // 3 meter explosion radius
        explosionDamage: 100.0,  // High damage for grenades
        physicsWorld: physicsWorld,
        enemySystem: enemySystem
      )
      activeProjectiles.append(projectile)

      logger.debug("🚀 Launched projectile at \(weaponPosition) with velocity \(initialVelocity)")
    }
  }

  /// Update all active projectiles
  private func updateProjectiles(deltaTime: Float) {
    guard let physicsWorld = physicsWorld else { return }

    let bodyInterface = physicsWorld.bodyInterface()
    let physicsSystem = physicsWorld.getPhysicsSystem()
    var projectilesToRemove: [Int] = []

    for (index, projectile) in activeProjectiles.enumerated() {
      // Check if projectile should be removed (lifetime expired)
      guard projectile.update(deltaTime: deltaTime) else {
        // Lifetime expired - explode
        projectile.explode()
        projectilesToRemove.append(index)
        continue
      }

      // Check if body is no longer in broad phase (removed somehow)
      guard bodyInterface.isInBroadPhase(projectile.bodyID) else {
        projectilesToRemove.append(index)
        continue
      }

      // Check if projectile hit something using collision detection
      let position = bodyInterface.getCenterOfMassPosition(projectile.bodyID)

      // Use a small sphere to check for collisions with static geometry
      let checkRadius: Float = 0.1
      let checkShape = SphereShape(radius: checkRadius)
      var baseOffset = RVec3(x: 0, y: 0, z: 0)
      let checkTransform = RMat44(
        1, 0, 0, position.x,
        0, 1, 0, position.y,
        0, 0, 1, position.z,
        0, 0, 0, 1
      )

      // Check for collisions with static bodies (layer 0)
      let collisions = physicsSystem.collideShapeAll(
        shape: checkShape,
        scale: Vec3(x: 1, y: 1, z: 1),
        centerOfMassTransform: checkTransform.cValue,
        baseOffset: &baseOffset
      )

      // If we hit something (and it's not ourselves), explode
      var hitSomething = false
      for collision in collisions {
        // Check if the collision is with a static body (not the projectile itself)
        // The projectile is dynamic, so if we collide with something else, we hit it
        if collision.bodyID2 != projectile.bodyID {
          hitSomething = true
          break
        }
      }

      // Also check if velocity dropped significantly (hit something and stopped)
      let velocity = bodyInterface.getLinearVelocity(projectile.bodyID)
      // Calculate speed manually for Jolt's Vec3
      let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
      if speed < 0.5 {
        hitSomething = true
      }

      if hitSomething {
        projectile.explode()
        projectilesToRemove.append(index)
        continue
      }
    }

    // Remove exploded/expired projectiles (in reverse order to maintain indices)
    for index in projectilesToRemove.reversed() {
      activeProjectiles.remove(at: index)
    }
  }

  /// Get active projectiles for rendering (returns positions)
  public func getActiveProjectilePositions() -> [vec3] {
    guard let physicsWorld = physicsWorld else { return [] }

    let bodyInterface = physicsWorld.bodyInterface()
    return activeProjectiles.map { projectile in
      let position = bodyInterface.getCenterOfMassPosition(projectile.bodyID)
      return vec3(position.x, position.y, position.z)
    }
  }
}
