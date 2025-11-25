import Jolt

@MainActor
final class CivilianEnemy: Enemy {
  override var moveSpeed: Float { 2.0 }  // Slower than player
  override var detectionRange: Float { 8.0 }
  override var attackRange: Float { 1.5 }
  override var maxHealth: Float { 50.0 }

  override func spawn(at position: vec3, rotation: Float, in physicsWorld: PhysicsWorld) {
    super.spawn(at: position, rotation: rotation, in: physicsWorld)
    state = .patrolling
  }

  override func attack(target: vec3) {
    logger.info("Civilian enemy attacking with weak melee")
    // TODO: Deal damage to player, play animation, etc.
  }
}
