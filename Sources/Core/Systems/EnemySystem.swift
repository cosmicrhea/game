import CJolt
import Foundation
import Jolt

@MainActor
public final class EnemySystem {
  private var enemies: [UUID: Enemy] = [:]
  private weak var physicsWorld: PhysicsWorld?
  private weak var playerController: PlayerController?
  
  public init(physicsWorld: PhysicsWorld, playerController: PlayerController) {
    self.physicsWorld = physicsWorld
    self.playerController = playerController
  }
  
  func update(deltaTime: Float) {
    guard let physicsWorld = physicsWorld,
          let playerController = playerController else { return }
    
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
}

