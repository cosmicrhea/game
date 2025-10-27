import Foundation

/// Renders prerendered environment scenes using depth-aware shaders
final class PrerenderedEnvironment {

  // Shader program
  private let shader: GLProgram

  // Images (which handle GL texture management)
  private let albedoImage: Image
  private let mistImage: Image

  // Fullscreen quad rendering
  private var vao: GLuint = 0
  private var vbo: GLuint = 0
  private var ebo: GLuint = 0

  // Camera parameters
  private let near: Float = 0.1
  private let far: Float = 100.0

  // Texture filtering toggle
  public var nearestNeighborFiltering: Bool = true

  init() throws {
    // Load the PrerenderedEnvironment shader
    do {
      shader = try GLProgram("Common/PrerenderedEnvironment")
      logger.trace("✅ PrerenderedEnvironment shader loaded successfully")
    } catch {
      logger.error("❌ Failed to load PrerenderedEnvironment shader: \(error)")
      throw error
    }

    // Load images using your Image class
    albedoImage = Image("Scenes/Renders/radar_office/1_1.png")
    mistImage = Image("Scenes/Renders/radar_office/m_1_1.png")
    logger.trace("✅ Images loaded successfully")
    logger.trace("🖼️ Albedo image: \(albedoImage.naturalSize), texture ID: \(albedoImage.textureID)")
    logger.trace("🌫️ Mist image: \(mistImage.naturalSize), texture ID: \(mistImage.textureID)")

    // Calculate aspect ratio correction
    let imageAspect = albedoImage.naturalSize.width / albedoImage.naturalSize.height
    logger.trace("📐 Image aspect ratio: \(imageAspect)")

    // Create fullscreen quad
    setupFullscreenQuad()
    logger.trace("✅ Fullscreen quad created")

    // Set initial texture filtering
    updateTextureFiltering()
  }

  deinit {
    cleanup()
  }

  private func setupFullscreenQuad() {
    // Fullscreen quad vertices: position (x, y) + texture coords (u, v)
    let vertices: [Float] = [
      -1.0, -1.0, 0.0, 0.0,  // bottom-left
      1.0, -1.0, 1.0, 0.0,  // bottom-right
      1.0, 1.0, 1.0, 1.0,  // top-right
      -1.0, 1.0, 0.0, 1.0,  // top-left
    ]

    let indices: [UInt32] = [
      0, 1, 2,  // first triangle
      0, 2, 3,  // second triangle
    ]

    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_STATIC_DRAW)

    // Position attribute (location 0)
    glVertexAttribPointer(0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), nil)
    glEnableVertexAttribArray(0)

    // Texture coordinate attribute (location 1)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride))
    glEnableVertexAttribArray(1)

    glBindVertexArray(0)
  }

  /// Update texture filtering based on the nearestNeighborFiltering toggle
  private func updateTextureFiltering() {
    let filterMode = nearestNeighborFiltering ? GL_NEAREST : GL_LINEAR

    // Update albedo texture filtering
    glBindTexture(GL_TEXTURE_2D, GLuint(albedoImage.textureID))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMode)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMode)

    // Update mist texture filtering
    glBindTexture(GL_TEXTURE_2D, GLuint(mistImage.textureID))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMode)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMode)

    glBindTexture(GL_TEXTURE_2D, 0)
    logger.trace("🔧 Updated texture filtering to: \(nearestNeighborFiltering ? "NEAREST" : "LINEAR")")
  }

  /// Toggle between nearest neighbor and linear filtering
  public func toggleFiltering() {
    nearestNeighborFiltering.toggle()
    updateTextureFiltering()
  }

  func render() {
    logger.trace("🎬 Rendering PrerenderedEnvironment...")
    shader.use()

    // Calculate viewport aspect ratio
    let viewportAspect = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let imageAspect = albedoImage.naturalSize.width / albedoImage.naturalSize.height
    let aspectCorrection = viewportAspect / imageAspect  // Try inverted

    // Set uniforms
    shader.setFloat("near", value: near)
    shader.setFloat("far", value: far)
    shader.setFloat("uAspectRatio", value: aspectCorrection)
    logger.trace("📐 Set uniforms: near=\(near), far=\(far), aspectCorrection=\(aspectCorrection)")

    // Bind textures using the Image's texture IDs
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, GLuint(albedoImage.textureID))
    shader.setInt("albedo_texture", value: 0)
    logger.trace("🖼️ Bound albedo texture: ID \(albedoImage.textureID)")

    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, GLuint(mistImage.textureID))
    shader.setInt("mist_texture", value: 1)
    logger.trace("🌫️ Bound mist texture: ID \(mistImage.textureID)")

    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, GLuint(mistImage.textureID))  // Use mist as depth too
    shader.setInt("depth_texture", value: 2)
    logger.trace("📏 Bound depth texture: ID \(mistImage.textureID)")

    // Draw fullscreen quad
    glBindVertexArray(vao)
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)
    logger.trace("✅ Drew fullscreen quad")
  }

  private func cleanup() {
    if vao != 0 {
      glDeleteVertexArrays(1, &vao)
      vao = 0
    }
    if vbo != 0 {
      glDeleteBuffers(1, &vbo)
      vbo = 0
    }
    if ebo != 0 {
      glDeleteBuffers(1, &ebo)
      ebo = 0
    }
    // Note: Images handle their own texture cleanup via GLTextureHandle
  }
}
