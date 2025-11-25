import CJolt
import Foundation
import Jolt

@MainActor
final class DogEnemy: Enemy {
  override var moveSpeed: Float { 4.0 }  // Faster than player
  override var detectionRange: Float { 12.0 }  // Better hearing/smell
  override var attackRange: Float { 1.0 }  // Bite range
  override var maxHealth: Float { 30.0 }  // Less health but faster

  // Smaller capsule for dog
  override func spawn(at position: vec3, rotation: Float, in physicsWorld: PhysicsWorld) {
    self.position = position
    self.rotation = rotation
    self.spawnPosition = position
    self.spawnRotation = rotation
    self.physicsWorld = physicsWorld
    self.health = maxHealth

    // Create smaller character controller for dog
    createDogCharacterController(in: physicsWorld)
    state = .patrolling
  }

  private func createDogCharacterController(in physicsWorld: PhysicsWorld) {
    // Smaller capsule for dog
    let capsuleRadius: Float = 0.25
    let capsuleHalfHeight: Float = 0.4
    let capsuleShape = CapsuleShape(halfHeight: capsuleHalfHeight, radius: capsuleRadius)

    let supportingPlane = Plane(normal: Vec3(x: 0, y: 1, z: 0), distance: -capsuleRadius)

    let characterSettings = CharacterVirtualSettings(
      up: Vec3(x: 0, y: 1, z: 0),
      supportingVolume: supportingPlane,
      shape: capsuleShape
    )

    let rotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))

    characterController = CharacterVirtual(
      settings: characterSettings,
      position: RVec3(x: position.x, y: position.y, z: position.z),
      rotation: rotationQuat,
      in: physicsWorld.getPhysicsSystem()
    )

    characterController?.mass = 20.0  // Lighter
    characterController?.maxStrength = 200.0
  }

  override func attack(target: vec3) {
    logger.info("Dog enemy biting")
    // TODO: Deal damage, play bite animation, etc.
  }
}
