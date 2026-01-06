import Foundation
import GLMath
import struct ImageFormats.Image
import struct ImageFormats.RGBA

/// Singleton manager for all particle emitters
@MainActor
public final class ParticleSystem {
  public static let shared = ParticleSystem()
  
  private var emitters: [ParticleEmitter] = []
  private let shader: GLProgram
  
  // Texture cache for particle textures
  private var textureCache: [String: GLuint] = [:]
  
  // Pending sub-effects to spawn (with delays)
  private struct PendingSubEffect {
    let effect: ParticleEffect
    let position: vec3
    let delay: Float
    var elapsed: Float = 0.0
  }
  private var pendingSubEffects: [PendingSubEffect] = []
  
  // Shared quad geometry for billboard rendering
  nonisolated(unsafe) private var quadVAO: GLuint = 0
  nonisolated(unsafe) private var quadVBO: GLuint = 0
  nonisolated(unsafe) private var quadEBO: GLuint = 0
  
  // Instance data buffers (reused each frame)
  nonisolated(unsafe) private var instancePositionBuffer: GLuint = 0
  nonisolated(unsafe) private var instanceSizeBuffer: GLuint = 0
  nonisolated(unsafe) private var instanceColorBuffer: GLuint = 0
  nonisolated(unsafe) private var instanceRotationBuffer: GLuint = 0
  
  private init() {
    // Load particle shader
    self.shader = try! GLProgram.cached("Common/particle", "Common/particle")
    
    // Create shared quad geometry
    setupQuadGeometry()
    setupInstanceBuffers()
  }
  
  nonisolated deinit {
    cleanup()
  }
  
  /// Create a new particle emitter
  public func createEmitter(effect: ParticleEffect, at position: vec3) -> ParticleEmitter {
    let emitter = ParticleEmitter(effect: effect, position: position)
    emitters.append(emitter)
    
    // Spawn sub-effects if any
    if let subEffects = effect.subEffects {
      for subEffect in subEffects {
        let subPosition = position + subEffect.offset
        if subEffect.delay <= 0.0 {
          // Spawn immediately
          _ = createEmitter(effect: subEffect.effect, at: subPosition)
        } else {
          // Schedule for later
          pendingSubEffects.append(PendingSubEffect(
            effect: subEffect.effect,
            position: subPosition,
            delay: subEffect.delay
          ))
        }
      }
    }
    
    return emitter
  }
  
  /// Update all particle emitters
  public func update(deltaTime: Float) {
    // Update all emitters
    for emitter in emitters {
      emitter.update(deltaTime: deltaTime)
    }
    
    // Remove dead emitters
    emitters.removeAll { !$0.isAlive }
    
    // Update pending sub-effects
    var newPending: [PendingSubEffect] = []
    for var pending in pendingSubEffects {
      pending.elapsed += deltaTime
      if pending.elapsed >= pending.delay {
        // Time to spawn!
        _ = createEmitter(effect: pending.effect, at: pending.position)
      } else {
        // Still waiting
        newPending.append(pending)
      }
    }
    pendingSubEffects = newPending
  }
  
  /// Render all particles
  public func render(projection: mat4, view: mat4, cameraPosition: vec3) {
    guard !emitters.isEmpty else { return }
    
    // Set up rendering state
    glEnable(GL_DEPTH_TEST)
    glDepthMask(false)  // Don't write depth for particles
    glEnable(GL_BLEND)
    glDisable(GL_CULL_FACE)
    
    // Use particle shader
    shader.use()
    shader.setMat4("projection", value: projection)
    shader.setMat4("view", value: view)
    shader.setVec3("cameraPosition", value: (cameraPosition.x, cameraPosition.y, cameraPosition.z))
    
    // Bind quad geometry
    glBindVertexArray(quadVAO)
    
    // Render each emitter
    for emitter in emitters {
      renderEmitter(emitter)
    }
    
    glBindVertexArray(0)
    
    // Restore depth mask
    glDepthMask(true)
  }
  
  /// Render a single emitter
  private func renderEmitter(_ emitter: ParticleEmitter) {
    let particles = emitter.getAliveParticles()
    guard !particles.isEmpty else { return }
    
    let effect = emitter.effectConfig
    
    // Load and bind texture if available
    var hasTexture = false
    if let texturePath = effect.texturePath {
      if let textureID = loadTexture(path: texturePath) {
        glActiveTexture(GL_TEXTURE0)
        glBindTexture(GL_TEXTURE_2D, textureID)
        shader.setInt("particleTexture", value: 0)
        hasTexture = true
      }
    }
    shader.setBool("hasTexture", value: hasTexture)
    
    // Set blend mode
    switch effect.blendMode {
    case .alpha:
      glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    case .additive:
      glBlendFunc(GL_SRC_ALPHA, GL_ONE)
    }
    
    // Prepare instance data
    var positions: [Float] = []
    var sizes: [Float] = []
    var colors: [Float] = []
    var rotations: [Float] = []
    
    positions.reserveCapacity(particles.count * 3)
    sizes.reserveCapacity(particles.count)
    colors.reserveCapacity(particles.count * 4)
    rotations.reserveCapacity(particles.count)
    
    for particle in particles {
      positions.append(particle.position.x)
      positions.append(particle.position.y)
      positions.append(particle.position.z)
      
      sizes.append(particle.size)
      
      colors.append(particle.color.x)
      colors.append(particle.color.y)
      colors.append(particle.color.z)
      colors.append(particle.color.w)
      
      rotations.append(particle.rotation)
    }
    
    // Upload instance data
    glBindBuffer(GL_ARRAY_BUFFER, instancePositionBuffer)
    positions.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_DYNAMIC_DRAW)
    }
    
    glBindBuffer(GL_ARRAY_BUFFER, instanceSizeBuffer)
    sizes.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_DYNAMIC_DRAW)
    }
    
    glBindBuffer(GL_ARRAY_BUFFER, instanceColorBuffer)
    colors.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_DYNAMIC_DRAW)
    }
    
    glBindBuffer(GL_ARRAY_BUFFER, instanceRotationBuffer)
    rotations.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_DYNAMIC_DRAW)
    }
    
    // Set up instance attributes
    // Position (location 1)
    glEnableVertexAttribArray(1)
    glBindBuffer(GL_ARRAY_BUFFER, instancePositionBuffer)
    glVertexAttribPointer(1, 3, GL_FLOAT, false, 0, nil)
    glVertexAttribDivisor(1, 1)
    
    // Size (location 2)
    glEnableVertexAttribArray(2)
    glBindBuffer(GL_ARRAY_BUFFER, instanceSizeBuffer)
    glVertexAttribPointer(2, 1, GL_FLOAT, false, 0, nil)
    glVertexAttribDivisor(2, 1)
    
    // Color (location 3)
    glEnableVertexAttribArray(3)
    glBindBuffer(GL_ARRAY_BUFFER, instanceColorBuffer)
    glVertexAttribPointer(3, 4, GL_FLOAT, false, 0, nil)
    glVertexAttribDivisor(3, 1)
    
    // Rotation (location 4)
    glEnableVertexAttribArray(4)
    glBindBuffer(GL_ARRAY_BUFFER, instanceRotationBuffer)
    glVertexAttribPointer(4, 1, GL_FLOAT, false, 0, nil)
    glVertexAttribDivisor(4, 1)
    
    // Draw instanced
    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, GLsizei(particles.count))
    
    // Disable instance attributes
    glVertexAttribDivisor(1, 0)
    glVertexAttribDivisor(2, 0)
    glVertexAttribDivisor(3, 0)
    glVertexAttribDivisor(4, 0)
    glDisableVertexAttribArray(1)
    glDisableVertexAttribArray(2)
    glDisableVertexAttribArray(3)
    glDisableVertexAttribArray(4)
  }
  
  /// Set up shared quad geometry for billboards
  private func setupQuadGeometry() {
    // Quad vertices (centered at origin, facing +Z)
    let quadVertices: [Float] = [
      // Position (x, y, z)
      -0.5, -0.5, 0.0,  // Bottom left
      0.5, -0.5, 0.0,   // Bottom right
      0.5, 0.5, 0.0,    // Top right
      -0.5, 0.5, 0.0,   // Top left
    ]
    
    let quadIndices: [UInt32] = [
      0, 1, 2,  // First triangle
      0, 2, 3,  // Second triangle
    ]
    
    glGenVertexArrays(1, &quadVAO)
    glGenBuffers(1, &quadVBO)
    glGenBuffers(1, &quadEBO)
    
    glBindVertexArray(quadVAO)
    
    // Vertex positions
    glBindBuffer(GL_ARRAY_BUFFER, quadVBO)
    quadVertices.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }
    
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadEBO)
    quadIndices.withUnsafeBytes { bytes in
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }
    
    // Position attribute (location 0)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)
    
    glBindVertexArray(0)
  }
  
  /// Set up instance data buffers
  private func setupInstanceBuffers() {
    glGenBuffers(1, &instancePositionBuffer)
    glGenBuffers(1, &instanceSizeBuffer)
    glGenBuffers(1, &instanceColorBuffer)
    glGenBuffers(1, &instanceRotationBuffer)
  }
  
  /// Cleanup resources
  nonisolated private func cleanup() {
    if quadVAO != 0 {
      var vao = quadVAO
      glDeleteVertexArrays(1, &vao)
    }
    if quadVBO != 0 {
      var vbo = quadVBO
      glDeleteBuffers(1, &vbo)
    }
    if quadEBO != 0 {
      var ebo = quadEBO
      glDeleteBuffers(1, &ebo)
    }
    if instancePositionBuffer != 0 {
      var buf = instancePositionBuffer
      glDeleteBuffers(1, &buf)
    }
    if instanceSizeBuffer != 0 {
      var buf = instanceSizeBuffer
      glDeleteBuffers(1, &buf)
    }
    if instanceColorBuffer != 0 {
      var buf = instanceColorBuffer
      glDeleteBuffers(1, &buf)
    }
    if instanceRotationBuffer != 0 {
      var buf = instanceRotationBuffer
      glDeleteBuffers(1, &buf)
    }
  }
  
  /// Clear all emitters
  public func clear() {
    emitters.removeAll()
    pendingSubEffects.removeAll()
  }
  
  /// Get total number of alive particles across all emitters
  public func getTotalParticleCount() -> Int {
    return emitters.reduce(0) { $0 + $1.getAliveParticles().count }
  }
  
  /// Load a texture from a path (cached)
  private func loadTexture(path: String) -> GLuint? {
    // Check cache first
    if let cached = textureCache[path] {
      return cached
    }
    
    // Check TextureCache.shared
    if let cached = TextureCache.shared.getCachedTexture(for: path) {
      textureCache[path] = cached
      return cached
    }
    
    // Try to load from Bundle.game
    guard let resourceURL = Bundle.game.resourceURL else {
      logger.warning("Failed to load particle texture: Bundle.game.resourceURL is nil")
      return nil
    }
    
    let url = resourceURL.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url) else {
      logger.warning("Failed to load particle texture data from: \(path)")
      return nil
    }
    
    let ext = url.pathExtension.lowercased()
    let raw = Array(data)
    
    // Decode image
    let loaded: ImageFormats.Image<ImageFormats.RGBA>?
    if ext == "png" {
      loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: raw)
    } else if ext == "webp" {
      loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: raw)
    } else {
      loaded = try? ImageFormats.Image<ImageFormats.RGBA>.load(from: raw)
    }
    
    guard let image = loaded else {
      logger.warning("Failed to decode particle texture: \(path)")
      return nil
    }
    
    // Upload to GPU
    var textureID: GLuint = 0
    glGenTextures(1, &textureID)
    glBindTexture(GL_TEXTURE_2D, textureID)
    
    // Set texture parameters for particles (clamp to edge, linear filtering)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    
    // Upload texture data
    image.bytes.withUnsafeBytes { bytes in
      glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA,
        GLsizei(image.width),
        GLsizei(image.height),
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        bytes.baseAddress
      )
    }
    
    // Cache the texture
    textureCache[path] = textureID
    TextureCache.shared.cacheTexture(textureID, for: path)
    
    logger.trace("Loaded particle texture: \(path) (ID: \(textureID))")
    return textureID
  }
}
