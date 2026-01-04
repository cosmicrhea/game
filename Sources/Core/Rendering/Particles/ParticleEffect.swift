import Foundation
@preconcurrency import GLMath

/// Configuration for a particle effect, defining emission behavior, particle properties, and visual appearance.
public struct ParticleEffect: Sendable {
  /// Unique identifier for the effect type
  public let name: String
  
  /// Emission configuration
  public var emissionMode: EmissionMode
  public var emissionRate: Float  // Particles per second (for continuous)
  public var burstCount: Int  // Particles per burst (for burst mode)
  public var duration: Float  // How long the emitter runs (0 = infinite)
  
  /// Particle lifetime
  public var lifetimeMin: Float
  public var lifetimeMax: Float
  
  /// Initial velocity configuration
  public var velocityMin: vec3
  public var velocityMax: vec3
  
  /// Forces applied to particles
  public var gravity: vec3
  public var wind: vec3
  
  /// Size configuration
  public var sizeStart: Float
  public var sizeEnd: Float
  public var sizeRandomness: Float  // Random variation (0-1)
  
  /// Color configuration
  public var colorStart: vec4
  public var colorEnd: vec4
  
  /// Rotation configuration
  public var rotationSpeedMin: Float
  public var rotationSpeedMax: Float
  
  /// Blending mode
  public var blendMode: BlendMode
  
  /// Maximum number of particles for this emitter
  public var maxParticles: Int
  
  /// Optional texture path for particle billboard (relative to Assets/)
  public var texturePath: String?
  
  /// Sub-effects to spawn when this effect is created (for effect chaining)
  public var subEffects: [SubEffect]?
  
  public init(
    name: String,
    emissionMode: EmissionMode,
    emissionRate: Float = 10.0,
    burstCount: Int = 50,
    duration: Float = 0.0,
    lifetimeMin: Float = 1.0,
    lifetimeMax: Float = 2.0,
    velocityMin: vec3 = vec3(-1, -1, -1),
    velocityMax: vec3 = vec3(1, 1, 1),
    gravity: vec3 = vec3(0, -9.81, 0),
    wind: vec3 = vec3(0, 0, 0),
    sizeStart: Float = 0.1,
    sizeEnd: Float = 0.1,
    sizeRandomness: Float = 0.0,
    colorStart: vec4 = vec4(1, 1, 1, 1),
    colorEnd: vec4 = vec4(1, 1, 1, 0),
    rotationSpeedMin: Float = 0.0,
    rotationSpeedMax: Float = 0.0,
    blendMode: BlendMode = .alpha,
    maxParticles: Int = 1000,
    texturePath: String? = nil,
    subEffects: [SubEffect]? = nil
  ) {
    self.name = name
    self.emissionMode = emissionMode
    self.emissionRate = emissionRate
    self.burstCount = burstCount
    self.duration = duration
    self.lifetimeMin = lifetimeMin
    self.lifetimeMax = lifetimeMax
    self.velocityMin = velocityMin
    self.velocityMax = velocityMax
    self.gravity = gravity
    self.wind = wind
    self.sizeStart = sizeStart
    self.sizeEnd = sizeEnd
    self.sizeRandomness = sizeRandomness
    self.colorStart = colorStart
    self.colorEnd = colorEnd
    self.rotationSpeedMin = rotationSpeedMin
    self.rotationSpeedMax = rotationSpeedMax
    self.blendMode = blendMode
    self.maxParticles = maxParticles
    self.texturePath = texturePath
    self.subEffects = subEffects
  }
}

/// A sub-effect that can be spawned as part of an effect chain
public struct SubEffect: Sendable {
  /// The effect to spawn
  public let effect: ParticleEffect
  /// Delay before spawning (in seconds)
  public let delay: Float
  /// Position offset from parent effect position
  public let offset: vec3
  
  public init(effect: ParticleEffect, delay: Float = 0.0, offset: vec3 = vec3(0, 0, 0)) {
    self.effect = effect
    self.delay = delay
    self.offset = offset
  }
}

/// Emission mode for particle effects
public enum EmissionMode: Sendable {
  case continuous  // Emit particles continuously at a rate
  case burst  // Emit all particles at once
}

/// Blending mode for particle rendering
public enum BlendMode: Sendable {
  case alpha  // Standard alpha blending
  case additive  // Additive blending for bright effects
}

// MARK: - Predefined Effects

extension ParticleEffect {
  // /// Explosion core: bright center flash
  // private static let explosionCore = ParticleEffect(
  //   name: "Explosion Core",
  //   emissionMode: .burst,
  //   burstCount: 5,  // Multiple particles for brighter flash
  //   duration: 0.0,
  //   lifetimeMin: 0.2,
  //   lifetimeMax: 0.4,
  //   velocityMin: vec3(-0.1, -0.1, -0.1),  // Minimal movement, stay centered
  //   velocityMax: vec3(0.1, 0.1, 0.1),
  //   gravity: vec3(0, 0, 0),
  //   wind: vec3(0, 0, 0),
  //   sizeStart: 0.5,
  //   sizeEnd: 2.0,  // Grow larger
  //   sizeRandomness: 0.1,
  //   colorStart: vec4(1.0, 1.0, 1.0, 1.0),  // White (texture provides color)
  //   colorEnd: vec4(1.0, 1.0, 1.0, 0.0),  // Fade out
  //   rotationSpeedMin: 0.0,  // No rotation for explosion core
  //   rotationSpeedMax: 0.0,
  //   blendMode: .additive,
  //   maxParticles: 5,
  //   texturePath: "Particles/explosion_1.png"
  // )
  
  // /// Explosion smoke: dark smoke that expands outward
  // private static let explosionSmoke = ParticleEffect(
  //   name: "Explosion Smoke",
  //   emissionMode: .burst,
  //   burstCount: 12,  // More particles for better coverage
  //   duration: 0.0,
  //   lifetimeMin: 1.5,
  //   lifetimeMax: 2.5,
  //   velocityMin: vec3(-1.0, 0.3, -1.0),  // Outward expansion, slight upward
  //   velocityMax: vec3(1.0, 1.5, 1.0),  // More controlled range
  //   gravity: vec3(0, -0.2, 0),  // Gentle downward drift
  //   wind: vec3(0, 0, 0),
  //   sizeStart: 0.6,
  //   sizeEnd: 2.0,  // Expand significantly
  //   sizeRandomness: 0.15,
  //   colorStart: vec4(0.15, 0.15, 0.15, 0.9),  // Dark gray
  //   colorEnd: vec4(0.05, 0.05, 0.05, 0.0),  // Fade out
  //   rotationSpeedMin: -1.0,  // Slow rotation for smoke
  //   rotationSpeedMax: 1.0,
  //   blendMode: .alpha,
  //   maxParticles: 12,
  //   texturePath: "Particles/black_smoke_1.png"
  // )
  
  // /// Explosion effect: composite effect that spawns core and smoke
  // public static let explosion = ParticleEffect(
  //   name: "Explosion",
  //   emissionMode: .burst,
  //   burstCount: 0,  // No particles from main effect, only sub-effects
  //   duration: 0.0,
  //   lifetimeMin: 0.0,
  //   lifetimeMax: 0.0,
  //   velocityMin: vec3(0, 0, 0),
  //   velocityMax: vec3(0, 0, 0),
  //   gravity: vec3(0, 0, 0),
  //   wind: vec3(0, 0, 0),
  //   sizeStart: 0.0,
  //   sizeEnd: 0.0,
  //   sizeRandomness: 0.0,
  //   colorStart: vec4(1, 1, 1, 1),
  //   colorEnd: vec4(1, 1, 1, 0),
  //   rotationSpeedMin: 0.0,
  //   rotationSpeedMax: 0.0,
  //   blendMode: .alpha,
  //   maxParticles: 0,
  //   texturePath: nil,
  //   subEffects: [
  //     SubEffect(effect: explosionCore, delay: 0.0, offset: vec3(0, 0, 0)),
  //     SubEffect(effect: explosionSmoke, delay: 0.0, offset: vec3(0, 0, 0))  // Spawn together
  //   ]
  // )
  
  // /// Water splash effect: short-lived particles with upward arc
  // public static let splash = ParticleEffect(
  //   name: "Splash",
  //   emissionMode: .burst,
  //   burstCount: 30,
  //   duration: 0.0,
  //   lifetimeMin: 0.3,
  //   lifetimeMax: 0.8,
  //   velocityMin: vec3(-2, 2, -2),
  //   velocityMax: vec3(2, 5, 2),
  //   gravity: vec3(0, -9.81, 0),
  //   wind: vec3(0, 0, 0),
  //   sizeStart: 0.15,
  //   sizeEnd: 0.05,
  //   sizeRandomness: 0.2,
  //   colorStart: vec4(0.4, 0.6, 1.0, 0.8),  // Light blue
  //   colorEnd: vec4(0.3, 0.5, 0.9, 0.0),  // Darker blue, fade out
  //   rotationSpeedMin: -2.0,
  //   rotationSpeedMax: 2.0,
  //   blendMode: .alpha,
  //   maxParticles: 30,
  //   texturePath: "Particles/generic.png"
  // )
  
  // /// Smoke effect: continuous emission with upward drift
  // public static let smoke = ParticleEffect(
  //   name: "Smoke",
  //   emissionMode: .continuous,
  //   emissionRate: 20.0,
  //   duration: 0.0,  // Infinite
  //   lifetimeMin: 2.0,
  //   lifetimeMax: 4.0,
  //   velocityMin: vec3(-0.5, 2, -0.5),
  //   velocityMax: vec3(0.5, 4, 0.5),
  //   gravity: vec3(0, 0.5, 0),  // Slight upward drift
  //   wind: vec3(0.2, 0, 0),  // Wind effect
  //   sizeStart: 0.1,
  //   sizeEnd: 0.5,
  //   sizeRandomness: 0.3,
  //   colorStart: vec4(0.3, 0.3, 0.3, 0.6),  // Gray
  //   colorEnd: vec4(0.1, 0.1, 0.1, 0.0),  // Dark gray, fade out
  //   rotationSpeedMin: -1.0,
  //   rotationSpeedMax: 1.0,
  //   blendMode: .alpha,
  //   maxParticles: 500,
  //   texturePath: "Particles/smoke_1.png"
  // )
  
  /// Blood effect: impact burst with physics-like trajectories
  public static let blood = ParticleEffect(
    name: "Blood",
    emissionMode: .burst,
    burstCount: 50,
    duration: 0.0,
    lifetimeMin: 0.5,
    lifetimeMax: 1.5,
    velocityMin: vec3(-3, 1, -3),
    velocityMax: vec3(3, 5, 3),
    gravity: vec3(0, -9.81, 0),
    wind: vec3(0, 0, 0),
    sizeStart: 0.08,
    sizeEnd: 0.05,
    sizeRandomness: 0.2,
    colorStart: vec4(0.7, 0.1, 0.1, 1.0),  // Dark red
    colorEnd: vec4(0.5, 0.05, 0.05, 0.0),  // Darker red, fade out
    rotationSpeedMin: -3.0,
    rotationSpeedMax: 3.0,
    blendMode: .alpha,
    maxParticles: 50,
    texturePath: "Particles/generic.png"
  )
  
  // /// Acid bubbles effect: continuous emission with upward float
  // public static let bubbles = ParticleEffect(
  //   name: "Bubbles",
  //   emissionMode: .continuous,
  //   emissionRate: 10.0,
  //   duration: 0.0,  // Infinite
  //   lifetimeMin: 3.0,
  //   lifetimeMax: 5.0,
  //   velocityMin: vec3(-0.2, 1.5, -0.2),
  //   velocityMax: vec3(0.2, 2.5, 0.2),
  //   gravity: vec3(0, 0.3, 0),  // Gentle upward
  //   wind: vec3(0, 0, 0),
  //   sizeStart: 0.1,
  //   sizeEnd: 0.12,  // Slight growth
  //   sizeRandomness: 0.3,
  //   colorStart: vec4(0.2, 0.8, 0.3, 0.7),  // Green
  //   colorEnd: vec4(0.1, 0.6, 0.2, 0.0),  // Darker green, fade out
  //   rotationSpeedMin: -0.5,
  //   rotationSpeedMax: 0.5,
  //   blendMode: .alpha,
  //   maxParticles: 200,
  //   texturePath: "Particles/bubble.png"
  // )
  
  /// Muzzle smoke effect: horizontal burst of smoke from gun barrel
  public static let muzzleSmoke = ParticleEffect(
    name: "Muzzle Smoke",
    emissionMode: .burst,
    burstCount: 40,
    duration: 0.0,
    lifetimeMin: 0.8,
    lifetimeMax: 1.5,
    velocityMin: vec3(3, -0.5, -1),  // Forward and slightly spread
    velocityMax: vec3(8, 1, 1),  // Strong forward, slight upward spread
    gravity: vec3(0, -0.5, 0),  // Slight downward drift
    wind: vec3(0, 0, 0),
    sizeStart: 0.08,
    sizeEnd: 0.25,  // Expand as smoke disperses
    sizeRandomness: 0.3,
    colorStart: vec4(0.4, 0.4, 0.4, 0.8),  // Light gray smoke
    colorEnd: vec4(0.2, 0.2, 0.2, 0.0),  // Darker, fade out
    rotationSpeedMin: -2.0,
    rotationSpeedMax: 2.0,
    blendMode: .alpha,
    maxParticles: 40,
    texturePath: "Particles/smoke_2.png"
  )
}

