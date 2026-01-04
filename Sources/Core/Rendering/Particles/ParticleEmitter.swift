import Foundation
import GLMath

/// Internal particle data structure
struct Particle {
  var position: vec3
  var velocity: vec3
  var lifetime: Float
  var age: Float
  var color: vec4
  var size: Float
  var rotation: Float
  var rotationSpeed: Float
  
  var isAlive: Bool {
    return age < lifetime
  }
  
  var normalizedAge: Float {
    guard lifetime > 0 else { return 0 }
    return min(1.0, age / lifetime)
  }
}

/// Manages a collection of particles for a single effect instance
@MainActor
public final class ParticleEmitter {
  private var particles: [Particle] = []
  private var effect: ParticleEffect
  private var position: vec3
  private var elapsedTime: Float = 0.0
  private var isActive: Bool = true
  
  /// Whether this emitter is still active (emitting or has living particles)
  var isAlive: Bool {
    if !isActive && particles.allSatisfy({ !$0.isAlive }) {
      return false
    }
    return true
  }
  
  init(effect: ParticleEffect, position: vec3) {
    self.effect = effect
    self.position = position
    
    // Pre-allocate particle array
    particles.reserveCapacity(effect.maxParticles)
    
    // Emit initial burst if needed
    if effect.emissionMode == .burst {
      emitBurst()
      isActive = false  // Burst effects only emit once
    }
  }
  
  /// Update emitter and all particles
  func update(deltaTime: Float) {
    elapsedTime += deltaTime
    
    // Check if emitter should stop
    if effect.duration > 0 && elapsedTime >= effect.duration {
      isActive = false
    }
    
    // Emit new particles for continuous effects
    if isActive && effect.emissionMode == .continuous {
      let particlesToEmit = effect.emissionRate * deltaTime
      emitContinuous(count: particlesToEmit)
    }
    
    // Update all particles
    for i in particles.indices {
      guard particles[i].isAlive else { continue }
      
      var particle = particles[i]
      particle.age += deltaTime
      
      // Apply forces
      particle.velocity += effect.gravity * deltaTime
      particle.velocity += effect.wind * deltaTime
      
      // Update position
      particle.position += particle.velocity * deltaTime
      
      // Update rotation
      particle.rotation += particle.rotationSpeed * deltaTime
      
      // Update size and color based on lifetime
      let t = particle.normalizedAge
      
      // Update size
      let sizeRange = effect.sizeEnd - effect.sizeStart
      particle.size = effect.sizeStart + sizeRange * t
      
      // Update color (linear interpolation)
      particle.color = vec4(
        effect.colorStart.x + (effect.colorEnd.x - effect.colorStart.x) * t,
        effect.colorStart.y + (effect.colorEnd.y - effect.colorStart.y) * t,
        effect.colorStart.z + (effect.colorEnd.z - effect.colorStart.z) * t,
        effect.colorStart.w + (effect.colorEnd.w - effect.colorStart.w) * t
      )
      
      particles[i] = particle
    }
    
    // Remove dead particles (optional optimization - could keep them for reuse)
    particles.removeAll { !$0.isAlive }
  }
  
  /// Emit a burst of particles
  private func emitBurst() {
    let count = min(effect.burstCount, effect.maxParticles)
    for _ in 0..<count {
      if particles.count < effect.maxParticles {
        particles.append(createParticle())
      }
    }
  }
  
  /// Emit particles continuously based on rate
  private func emitContinuous(count: Float) {
    var remaining = count
    while remaining >= 1.0 && particles.count < effect.maxParticles {
      particles.append(createParticle())
      remaining -= 1.0
    }
    
    // Handle fractional emission
    if remaining > 0 && Float.random(in: 0..<1) < remaining && particles.count < effect.maxParticles {
      particles.append(createParticle())
    }
  }
  
  /// Create a new particle with random properties
  private func createParticle() -> Particle {
    // Random lifetime
    let lifetime = Float.random(in: effect.lifetimeMin...effect.lifetimeMax)
    
    // Random velocity
    let velX = Float.random(in: effect.velocityMin.x...effect.velocityMax.x)
    let velY = Float.random(in: effect.velocityMin.y...effect.velocityMax.y)
    let velZ = Float.random(in: effect.velocityMin.z...effect.velocityMax.z)
    let velocity = vec3(velX, velY, velZ)
    
    // Random size with variation
    let sizeVariation = Float.random(in: -effect.sizeRandomness...effect.sizeRandomness)
    let size = effect.sizeStart * (1.0 + sizeVariation)
    
    // Random rotation speed
    let rotationSpeed = Float.random(in: effect.rotationSpeedMin...effect.rotationSpeedMax)
    
    return Particle(
      position: position,
      velocity: velocity,
      lifetime: lifetime,
      age: 0.0,
      color: effect.colorStart,
      size: size,
      rotation: Float.random(in: 0...(2 * Float.pi)),
      rotationSpeed: rotationSpeed
    )
  }
  
  /// Get all alive particles for rendering
  func getAliveParticles() -> [Particle] {
    return particles.filter { $0.isAlive }
  }
  
  /// Get the effect configuration
  var effectConfig: ParticleEffect {
    return effect
  }
  
  /// Update emitter position (for moving emitters)
  func setPosition(_ newPosition: vec3) {
    self.position = newPosition
  }
  
  /// Stop emitting new particles (existing particles continue)
  func stop() {
    isActive = false
  }
  
  /// Update the effect configuration (for live editing)
  func setEffect(_ newEffect: ParticleEffect) {
    self.effect = newEffect
  }
}

