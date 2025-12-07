import CJolt
import Foundation
import Jolt
import Logging

/// Data extracted from scene nodes for spawning enemies
public struct EnemySpawnPoint {
  public let position: vec3
  public let rotation: Float
  public let typeName: String

  public init(position: vec3, rotation: Float, typeName: String) {
    self.position = position
    self.rotation = rotation
    self.typeName = typeName
  }
}

@MainActor
public final class EnemySystem {
  private static let logger = Logger(label: "EnemySystem")
  private var enemies: [UUID: Enemy] = [:]
  private weak var physicsWorld: PhysicsWorld?
  private weak var playerController: PlayerController?

  public init(physicsWorld: PhysicsWorld, playerController: PlayerController) {
    self.physicsWorld = physicsWorld
    self.playerController = playerController
  }

  func update(deltaTime: Float) {
    guard let physicsWorld = physicsWorld,
      let playerController = playerController
    else { return }

    let playerPosition = playerController.position

    // Update all enemies
    for enemy in enemies.values {
      enemy.update(
        deltaTime: deltaTime,
        playerPosition: playerPosition,
        physicsWorld: physicsWorld
      )
    }

    // Remove dead enemies
    enemies = enemies.filter { $0.value.isAlive }
  }

  func spawnEnemy<T: Enemy>(_ enemyType: T.Type, at position: vec3, rotation: Float) -> T? {
    guard let physicsWorld = physicsWorld else { return nil }

    let enemy = enemyType.init()
    enemy.spawn(at: position, rotation: rotation, in: physicsWorld)
    enemies[enemy.id] = enemy

    return enemy
  }

  /// Spawn enemies from extracted spawn points
  /// - Parameter spawnPoints: Array of spawn point data extracted from scene
  /// - Returns: Number of enemies successfully spawned
  @discardableResult
  func spawnFromPoints(_ spawnPoints: [EnemySpawnPoint]) -> Int {
    var spawnedCount = 0

    for point in spawnPoints {
      // Map type name to concrete enemy type
      let enemyType: Enemy.Type
      switch point.typeName.lowercased() {
      case "civilian":
        enemyType = CivilianEnemy.self
      case "dog":
        enemyType = DogEnemy.self
      default:
        Self.logger.warning("Unknown enemy type '\(point.typeName)'")
        continue
      }

      // Adjust Y position to account for capsule half-height (enemies spawn at center)
      let capsuleHalfHeight: Float = 0.8
      let adjustedPosition = vec3(point.position.x, point.position.y + capsuleHalfHeight, point.position.z)

      if let _ = spawnEnemy(enemyType, at: adjustedPosition, rotation: point.rotation) {
        spawnedCount += 1
        Self.logger.trace("Spawned \(point.typeName) enemy at \(point.position)")
      } else {
        Self.logger.warning("Failed to spawn \(point.typeName) enemy")
      }
    }

    if spawnedCount > 0 {
      Self.logger.debug("Spawned \(spawnedCount) enemies from spawn points")
    }

    return spawnedCount
  }

  func removeEnemy(_ id: UUID) {
    enemies[id]?.despawn()
    enemies.removeValue(forKey: id)
  }

  func clearAll() {
    for enemy in enemies.values {
      enemy.despawn()
    }
    enemies.removeAll()
  }

  var aliveEnemies: [Enemy] {
    enemies.values.filter { $0.isAlive }
  }

  /// Find an enemy by its character controller's inner body ID
  func findEnemy(byCharacterID characterID: CharacterID) -> Enemy? {
    return enemies.values.first { enemy in
      guard let characterController = enemy.characterController else { return false }
      return characterController.id == characterID
    }
  }

  /// Find an enemy by checking if a raycast hit its character controller
  func findEnemy(hitByRaycast hit: RayHit, in physicsWorld: PhysicsWorld) -> Enemy? {
    // For character controllers, we need to check if the hit body is the inner body
    // of any enemy's character controller
    let hitBodyID = hit.bodyID
    return enemies.values.first { enemy in
      guard let characterController = enemy.characterController else { return false }
      return characterController.getInnerBodyID() == hitBodyID
    }
  }
}
