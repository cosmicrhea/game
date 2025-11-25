import CJolt
import Foundation
import Jolt

enum EnemyState {
  case idle
  case patrolling
  case chasing
  case attacking
  case dead
}

@MainActor
class Enemy {
  let id = UUID()
  var position: vec3 = vec3(0, 0, 0)
  var rotation: Float = 0.0
  var health: Float = 100.0
  var maxHealth: Float { 100.0 } // Override in subclasses
  var isAlive: Bool { health > 0 }
  
  // Override these in subclasses
  var moveSpeed: Float { 3.0 } // Default speed
  var detectionRange: Float { 8.0 } // Default detection range
  var attackRange: Float { 1.5 } // Default attack range
  
  var state: EnemyState = .idle
  var targetPosition: vec3?
  
  var characterController: CharacterVirtual?
  weak var physicsWorld: PhysicsWorld?
  
  var spawnPosition: vec3 = vec3(0, 0, 0)
  var spawnRotation: Float = 0.0
  
  required init() {}
  
  // Subclasses can override for custom behavior
  func spawn(at position: vec3, rotation: Float, in physicsWorld: PhysicsWorld) {
    self.position = position
    self.rotation = rotation
    self.spawnPosition = position
    self.spawnRotation = rotation
    self.physicsWorld = physicsWorld
    self.health = maxHealth
    
    createCharacterController(in: physicsWorld)
    state = .idle
  }
  
  func despawn() {
    characterController = nil
    state = .dead
  }
  
  func update(deltaTime: Float, playerPosition: vec3, physicsWorld: PhysicsWorld) {
    guard isAlive else { return }
    guard let characterController = characterController else { return }
    
    updateState(playerPosition: playerPosition)
    
    switch state {
    case .idle:
      handleIdle(deltaTime: deltaTime)
    case .patrolling:
      handlePatrolling(deltaTime: deltaTime, playerPosition: playerPosition)
    case .chasing:
      handleChasing(deltaTime: deltaTime, playerPosition: playerPosition)
    case .attacking:
      handleAttacking(deltaTime: deltaTime, playerPosition: playerPosition)
    case .dead:
      break
    }
    
    updatePhysics(deltaTime: deltaTime, physicsWorld: physicsWorld)
    
    // Read position from character controller
    let characterPos = characterController.position
    position = vec3(characterPos.x, characterPos.y, characterPos.z)
  }
  
  // Subclasses can override for custom attack behavior
  func attack(target: vec3) {
    logger.trace("Enemy \(id) attacking target at \(target)")
  }
  
  func takeDamage(_ amount: Float) {
    health = max(0, health - amount)
    if health <= 0 {
      state = .dead
    }
  }
  
  // MARK: - Private/Protected Methods
  
  private func updateState(playerPosition: vec3) {
    guard state != .dead else { return }
    
    let distanceToPlayer = length(position - playerPosition)
    
    if distanceToPlayer <= attackRange {
      state = .attacking
    } else if distanceToPlayer <= detectionRange {
      state = .chasing
      targetPosition = playerPosition
    } else if state == .chasing {
      state = .patrolling
      targetPosition = spawnPosition
    }
  }
  
  private func handleIdle(deltaTime: Float) {
    // Idle behavior
  }
  
  private func handlePatrolling(deltaTime: Float, playerPosition: vec3) {
    guard let target = targetPosition else {
      targetPosition = spawnPosition
      return
    }
    moveTowards(target: target, deltaTime: deltaTime)
  }
  
  private func handleChasing(deltaTime: Float, playerPosition: vec3) {
    targetPosition = playerPosition
    moveTowards(target: playerPosition, deltaTime: deltaTime)
  }
  
  private func handleAttacking(deltaTime: Float, playerPosition: vec3) {
    let direction = normalize(playerPosition - position)
    rotation = atan2(direction.x, direction.z)
    performAttack(target: playerPosition)
  }
  
  private func performAttack(target: vec3) {
    attack(target: target)
  }
  
  private func moveTowards(target: vec3, deltaTime: Float) {
    guard let characterController = characterController else { return }
    
    let direction = normalize(target - position)
    let distance = length(target - position)
    
    rotation = atan2(direction.x, direction.z)
    
    if distance > 0.5 {
      let velocity = Vec3(
        x: direction.x * moveSpeed,
        y: characterController.linearVelocity.y,
        z: direction.z * moveSpeed
      )
      characterController.linearVelocity = velocity
    } else {
      var velocity = characterController.linearVelocity
      velocity.x = 0
      velocity.z = 0
      characterController.linearVelocity = velocity
    }
  }
  
  private func updatePhysics(deltaTime: Float, physicsWorld: PhysicsWorld) {
    guard let characterController = characterController else { return }
    guard physicsWorld.isReady else { return }
    
    let rotationQuat = Quat(x: 0, y: sin(rotation / 2), z: 0, w: cos(rotation / 2))
    characterController.rotation = rotationQuat
    
    physicsWorld.update(deltaTime: deltaTime, collisionSteps: 1)
    
    let characterLayer: ObjectLayer = 2
    characterController.update(
      deltaTime: deltaTime,
      layer: characterLayer,
      in: physicsWorld.getPhysicsSystem()
    )
  }
  
  func createCharacterController(in physicsWorld: PhysicsWorld) {
    let capsuleRadius: Float = 0.4
    let capsuleHalfHeight: Float = 0.8
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
    
    characterController?.mass = 70.0
    characterController?.maxStrength = 500.0
  }
}

