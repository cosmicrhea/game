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

  // MARK: - Debug Rendering

  /// Projects a 3D world position to screen coordinates
  private func projectToScreen(position: vec3, projection: mat4, view: mat4, viewportSize: Size) -> Point? {
    let worldPos = vec4(position.x, position.y, position.z, 1.0)
    let clipPos = projection * view * worldPos
    guard abs(clipPos.w) > 0.0001 else { return nil }

    let ndcX = clipPos.x / clipPos.w
    let ndcY = clipPos.y / clipPos.w
    guard ndcX.isFinite && ndcY.isFinite else { return nil }

    let halfWidth = viewportSize.width * 0.5
    let halfHeight = viewportSize.height * 0.5
    let screenX = halfWidth + ndcX * halfWidth
    let screenY = halfHeight + ndcY * halfHeight
    return Point(screenX, screenY)
  }

  /// Draws debug overlay for all alive enemies (health bars and state labels)
  func drawDebugOverlay(projection: mat4, view: mat4) {
    let viewportSize = Engine.viewportSize
    let aliveEnemies = self.aliveEnemies

    for enemy in aliveEnemies {
      // Position above enemy (adjust Y offset based on enemy type)
      let yOffset: Float = enemy is DogEnemy ? 0.6 : 1.2
      let worldPosition = vec3(enemy.position.x, enemy.position.y + yOffset, enemy.position.z)

      guard
        let screenPoint = projectToScreen(
          position: worldPosition,
          projection: projection,
          view: view,
          viewportSize: viewportSize
        )
      else { continue }

      // Skip if off-screen
      guard screenPoint.x >= -50 && screenPoint.x <= viewportSize.width + 50,
        screenPoint.y >= -50 && screenPoint.y <= viewportSize.height + 50
      else { continue }

      // Draw health bar
      let barWidth: Float = 60.0
      let barHeight: Float = 6.0
      let healthPercent = enemy.health / enemy.maxHealth

      // Background (red/dark)
      let bgRect = Rect(
        x: screenPoint.x - barWidth * 0.5,
        y: screenPoint.y - 20,
        width: barWidth,
        height: barHeight
      )
      bgRect.fill(with: Color(red: 0.3, green: 0.0, blue: 0.0, alpha: 0.8))

      // Health (green)
      let healthWidth = barWidth * healthPercent
      if healthWidth > 0 {
        let healthRect = Rect(
          x: screenPoint.x - barWidth * 0.5,
          y: screenPoint.y - 20,
          width: healthWidth,
          height: barHeight
        )
        healthRect.fill(with: Color(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.9))
      }

      // Border
      bgRect.frame(with: Color(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.9), lineWidth: 1.0)

      // State label
      let stateString: String
      switch enemy.state {
      case .idle: stateString = "Idle"
      case .patrolling: stateString = "Patrol"
      case .chasing: stateString = "Chase"
      case .attacking: stateString = "Attack"
      case .dead: stateString = "Dead"
      }

      stateString.draw(
        at: Point(screenPoint.x, screenPoint.y - 35),
        style: .itemDescription.withMonospacedDigits(true),
        anchor: .center
      )
    }
  }
}
