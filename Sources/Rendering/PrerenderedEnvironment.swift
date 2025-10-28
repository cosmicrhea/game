import Foundation

/// Renders prerendered environment scenes using depth-aware shaders
final class PrerenderedEnvironment {

  // Shader program
  private let shader: GLProgram

  // Images (which handle GL texture management)
  private var albedoImages: [Image] = []
  private var mistImages: [Image] = []

  // Fullscreen quad rendering
  private var vao: GLuint = 0
  private var vbo: GLuint = 0
  private var ebo: GLuint = 0

  // Camera parameters
  private let near: Float = 0.1
  private let far: Float = 100.0

  // Texture filtering toggle
  public var nearestNeighborFiltering: Bool = true

  // Frame animation
  private var currentFrame: Int = 0
  private var totalFrames: Int = 0
  private var lastFrameTime: Double = 0
  private let targetFPS: Double = 60.0
  private let frameDuration: Double = 1.0 / 60.0

  // Scene configuration
  private let scenePath: String
  private let cameraName: String

  init(scenePath: String = "Scenes/Renders/radar_office", cameraName: String = "1") throws {
    self.scenePath = scenePath
    self.cameraName = cameraName

    // Load the PrerenderedEnvironment shader
    do {
      shader = try GLProgram("Common/PrerenderedEnvironment")
      logger.trace("✅ PrerenderedEnvironment shader loaded successfully")
    } catch {
      logger.error("❌ Failed to load PrerenderedEnvironment shader: \(error)")
      throw error
    }

    // Discover and load all frames
    try discoverAndLoadFrames()
    logger.trace("✅ Loaded \(totalFrames) frames for camera '\(cameraName)'")

    // Create fullscreen quad
    setupFullscreenQuad()
    logger.trace("✅ Fullscreen quad created")

    // Set initial texture filtering
    updateTextureFiltering()

    // Initialize timing
    lastFrameTime = GLFWSession.currentTime
  }

  deinit {
    cleanup()
  }

  /// Discover and load all frames for the specified camera
  private func discoverAndLoadFrames() throws {
    // Find all frame files matching the pattern "frameNumber_cameraName.png"
    let fileManager = FileManager.default
    guard let resourcePath = #bundle.resourcePath else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find resource path"]
      )
    }

    let sceneDirectory = "\(resourcePath)/\(scenePath)"
    let contents = try fileManager.contentsOfDirectory(atPath: sceneDirectory)

    // Filter for albedo frames (not mist frames which start with 'm_')
    // Pattern: frameNumber_cameraName.png (e.g., "1_1.png", "2_1.png", etc.)
    // We want files that match exactly: [number]_[cameraName].png
    let albedoFrames = contents.filter { filename in
      // Must not start with 'm_' (mist files)
      guard !filename.hasPrefix("m_") else { return false }

      // Must end with "_\(cameraName).png"
      guard filename.hasSuffix("_\(cameraName).png") else { return false }

      // Extract the part before "_\(cameraName).png" to check if it's just a number
      let suffix = "_\(cameraName).png"
      let prefix = String(filename.dropLast(suffix.count))

      // Check if the prefix is just a number (no additional text)
      return prefix.allSatisfy { $0.isNumber }
    }.sorted()

    logger.trace("🎬 Found \(albedoFrames.count) frames for camera '\(cameraName)': \(albedoFrames)")

    guard !albedoFrames.isEmpty else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "No frames found for camera '\(cameraName)' in scene '\(scenePath)'"])
    }

    totalFrames = albedoFrames.count
    logger.trace("🎬 Found \(totalFrames) frames: \(albedoFrames)")

    // Load all frames
    albedoImages.reserveCapacity(totalFrames)
    mistImages.reserveCapacity(totalFrames)

    for frameFilename in albedoFrames {
      // Load albedo frame
      let albedoPath = "\(scenePath)/\(frameFilename)"
      let albedoImage = Image(albedoPath)
      albedoImages.append(albedoImage)

      // Load corresponding mist frame
      let mistFilename = "m_\(frameFilename)"
      let mistPath = "\(scenePath)/\(mistFilename)"
      let mistImage = Image(mistPath)
      mistImages.append(mistImage)

      logger.trace("📸 Loaded frame: \(frameFilename) -> albedo: \(albedoImage.textureID), mist: \(mistImage.textureID)")
    }
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

    // Update all albedo texture filtering
    for albedoImage in albedoImages {
      glBindTexture(GL_TEXTURE_2D, GLuint(albedoImage.textureID))
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMode)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMode)
    }

    // Update all mist texture filtering
    for mistImage in mistImages {
      glBindTexture(GL_TEXTURE_2D, GLuint(mistImage.textureID))
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filterMode)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filterMode)
    }

    glBindTexture(GL_TEXTURE_2D, 0)
    logger.trace(
      "🔧 Updated texture filtering to: \(nearestNeighborFiltering ? "NEAREST" : "LINEAR") for \(totalFrames) frames")
  }

  /// Toggle between nearest neighbor and linear filtering
  public func toggleFiltering() {
    nearestNeighborFiltering.toggle()
    updateTextureFiltering()
  }

  /// Update frame animation at 30 FPS
  public func update() {
    let currentTime = GLFWSession.currentTime
    let deltaTime = currentTime - lastFrameTime

    if deltaTime >= frameDuration {
      currentFrame = (currentFrame + 1) % totalFrames
      lastFrameTime = currentTime
      logger.trace("🎬 Advanced to frame \(currentFrame)/\(totalFrames)")
    }
  }

  func render() {
    guard totalFrames > 0 else {
      logger.error("❌ No frames loaded, cannot render")
      return
    }

    logger.trace("🎬 Rendering PrerenderedEnvironment frame \(currentFrame)/\(totalFrames)...")
    shader.use()

    // Get current frame images
    let currentAlbedoImage = albedoImages[currentFrame]
    let currentMistImage = mistImages[currentFrame]

    // Calculate viewport aspect ratio
    let viewportAspect = Float(Engine.viewportSize.width) / Float(Engine.viewportSize.height)
    let imageAspect = currentAlbedoImage.naturalSize.width / currentAlbedoImage.naturalSize.height
    let aspectCorrection = viewportAspect / imageAspect  // Try inverted

    // Set uniforms
    shader.setFloat("near", value: near)
    shader.setFloat("far", value: far)
    shader.setFloat("uAspectRatio", value: aspectCorrection)
    logger.trace("📐 Set uniforms: near=\(near), far=\(far), aspectCorrection=\(aspectCorrection)")

    // Bind textures using the current frame's texture IDs
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, GLuint(currentAlbedoImage.textureID))
    shader.setInt("albedo_texture", value: 0)
    logger.trace("🖼️ Bound albedo texture: ID \(currentAlbedoImage.textureID)")

    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, GLuint(currentMistImage.textureID))
    shader.setInt("mist_texture", value: 1)
    logger.trace("🌫️ Bound mist texture: ID \(currentMistImage.textureID)")

    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, GLuint(currentMistImage.textureID))  // Use mist as depth too
    shader.setInt("depth_texture", value: 2)
    logger.trace("📏 Bound depth texture: ID \(currentMistImage.textureID)")

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
