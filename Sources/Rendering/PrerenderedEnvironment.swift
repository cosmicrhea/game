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
  public var near: Float = 0.1
  public var far: Float = 100.0

  // Texture filtering toggle
  @Editable public var nearestNeighborFiltering: Bool = true

  // Debug mist visualization
  @Editable public var debugMistMode: Int = 0  // 0 = normal, 1 = mist only, 2 = mist overlay
  @Editable(range: 0.0...1.0) public var mistOverlayOpacity: Float = 0.5

  // Camera selection for editor
  @Editable public var selectedCamera: String = "1" {
    didSet {
      if selectedCamera != oldValue {
        try? switchToCamera(selectedCamera)
      }
    }
  }

  // Frame animation
  private var currentFrame: Int = 0
  private var totalFrames: Int = 0
  private var lastFrameTime: Double = 0
  private let targetFPS: Double = 60.0
  private let frameDuration: Double = 1.0 / 60.0

  // Scene configuration
  private let scenePath: String
  private var availableCameras: [String] = []
  private var currentCameraIndex: Int = 0

  init(_ sceneName: String, cameraName: String = "1") throws {
    self.scenePath = "Scenes/Renders/\(sceneName)"

    // Load the PrerenderedEnvironment shader
    do {
      shader = try GLProgram("Common/PrerenderedEnvironment")
      logger.trace("✅ PrerenderedEnvironment shader loaded successfully")
    } catch {
      logger.error("❌ Failed to load PrerenderedEnvironment shader: \(error)")
      throw error
    }

    // Discover all available cameras
    try discoverAvailableCameras()

    // Set initial camera
    if let initialCameraIndex = availableCameras.firstIndex(of: cameraName) {
      currentCameraIndex = initialCameraIndex
      selectedCamera = cameraName
    } else if !availableCameras.isEmpty {
      currentCameraIndex = 0
      selectedCamera = availableCameras[0]
      logger.warning("⚠️ Camera '\(cameraName)' not found, using first available camera: '\(availableCameras[0])'")
    } else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "No cameras found in scene '\(scenePath)'"])
    }

    // Discover and load all frames for the current camera
    try discoverAndLoadFrames()
    logger.trace("✅ Loaded \(totalFrames) frames for camera '\(currentCameraName)'")

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

  /// Discover all available cameras in the scene
  private func discoverAvailableCameras() throws {
    let fileManager = FileManager.default

    guard let resourcePath = Bundle.game.resourcePath else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find resource path"]
      )
    }

    let sceneDirectory = "\(resourcePath)/\(scenePath)"
    let contents = try fileManager.contentsOfDirectory(atPath: sceneDirectory)

    // Find all unique camera names by looking at frame files
    // Pattern: frameNumber_cameraName.png (e.g., "1_1.png", "2_1.png", etc.)
    var cameraNames: Set<String> = []

    for filename in contents {
      // Must not start with 'm_' (mist files)
      guard !filename.hasPrefix("m_") else { continue }

      // Must end with ".png"
      guard filename.hasSuffix(".png") else { continue }

      // Extract camera name by finding the last underscore before .png
      if let lastUnderscoreIndex = filename.lastIndex(of: "_") {
        let cameraName = String(
          filename[filename.index(after: lastUnderscoreIndex)..<filename.index(filename.endIndex, offsetBy: -4)])
        cameraNames.insert(cameraName)
      }
    }

    availableCameras = Array(cameraNames).sorted()
    logger.trace("📷 Found cameras: \(availableCameras)")
  }

  /// Get the current camera name
  private var currentCameraName: String {
    return availableCameras[currentCameraIndex]
  }

  /// Discover and load all frames for the current camera
  private func discoverAndLoadFrames() throws {
    // Find all frame files matching the pattern "frameNumber_cameraName.png"
    let fileManager = FileManager.default
    guard let resourcePath = Bundle.game.resourcePath else {
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

      // Must end with "_\(currentCameraName).png"
      guard filename.hasSuffix("_\(currentCameraName).png") else { return false }

      // Extract the part before "_\(currentCameraName).png" to check if it's just a number
      let suffix = "_\(currentCameraName).png"
      let prefix = String(filename.dropLast(suffix.count))

      // Check if the prefix is just a number (no additional text)
      return prefix.allSatisfy { $0.isNumber }
    }.sorted(using: .localizedStandard)

    logger.trace("🎬 Found \(albedoFrames.count) frames for camera '\(currentCameraName)': \(albedoFrames)")

    guard !albedoFrames.isEmpty else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "No frames found for camera '\(currentCameraName)' in scene '\(scenePath)'"
        ])
    }

    totalFrames = albedoFrames.count
    logger.trace("🎬 Found \(totalFrames) frames: \(albedoFrames)")

    // Clear old frames before loading new ones
    albedoImages.removeAll()
    mistImages.removeAll()

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

  /// Switch to a specific camera by name
  public func switchToCamera(_ cameraName: String) throws {
    guard let cameraIndex = availableCameras.firstIndex(of: cameraName) else {
      throw NSError(
        domain: "PrerenderedEnvironment", code: 4,
        userInfo: [
          NSLocalizedDescriptionKey: "Camera '\(cameraName)' not found. Available cameras: \(availableCameras)"
        ])
    }

    switchToCamera(at: cameraIndex)
  }

  /// Switch to camera at specific index
  public func switchToCamera(at index: Int) {
    guard index >= 0 && index < availableCameras.count else {
      logger.error("❌ Invalid camera index \(index). Available cameras: \(availableCameras)")
      return
    }

    currentCameraIndex = index
    selectedCamera = currentCameraName  // Update the editable property
    logger.info("📷 Switched to camera '\(currentCameraName)' (index \(index))")

    // Reload frames for the new camera
    do {
      try discoverAndLoadFrames()

      // Reset animation state for the new camera
      currentFrame = 0
      lastFrameTime = GLFWSession.currentTime

      logger.trace("✅ Reloaded frames for camera '\(currentCameraName)' and reset animation")
    } catch {
      logger.error("❌ Failed to reload frames for camera '\(currentCameraName)': \(error)")
    }
  }

  /// Cycle to next camera
  public func cycleToNextCamera() {
    let nextIndex = (currentCameraIndex + 1) % availableCameras.count
    switchToCamera(at: nextIndex)
  }

  /// Cycle to previous camera
  public func cycleToPreviousCamera() {
    let prevIndex = (currentCameraIndex - 1 + availableCameras.count) % availableCameras.count
    switchToCamera(at: prevIndex)
  }

  /// Switch to camera 0 (special debug camera) if it exists
  public func switchToDebugCamera() {
    if let debugIndex = availableCameras.firstIndex(of: "0") {
      switchToCamera(at: debugIndex)
    } else {
      logger.warning("⚠️ Debug camera '0' not found. Available cameras: \(availableCameras)")
    }
  }

  /// Get available cameras for debugging/UI
  public func getAvailableCameras() -> [String] {
    return availableCameras
  }

  /// Get current camera name for debugging/UI
  public func getCurrentCameraName() -> String {
    return currentCameraName
  }

  /// Get current camera index for debugging/UI
  public func getCurrentCameraIndex() -> Int {
    return currentCameraIndex
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

  func render(projectionMatrix: mat4) {
    guard totalFrames > 0 else {
      logger.error("❌ No frames loaded, cannot render")
      return
    }

    logger.trace("🎬 Rendering PrerenderedEnvironment frame \(currentFrame)/\(totalFrames)...")
    shader.use()

    // Ensure background writes depth for integration with 3D
    glEnable(GL_DEPTH_TEST)
    glDepthMask(true)
    glDepthFunc(GL_ALWAYS)  // always write our gl_FragDepth

    // Get current frame images
    let currentAlbedoImage = albedoImages[currentFrame]
    let currentMistImage = mistImages[currentFrame]

    // Set uniforms
    shader.setFloat("near", value: near)
    shader.setFloat("far", value: far)
    shader.setMat4("view_to_clip_matrix", value: projectionMatrix)
    shader.setInt("debugMistMode", value: Int32(debugMistMode))
    shader.setFloat("mistOverlayOpacity", value: mistOverlayOpacity)
    logger.trace("📐 Set uniforms: near=\(near), far=\(far), debugMistMode=\(debugMistMode)")

    // Bind textures using the current frame's texture IDs
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, GLuint(currentAlbedoImage.textureID))
    shader.setInt("albedo_texture", value: 0)
    logger.trace("🖼️ Bound albedo texture: ID \(currentAlbedoImage.textureID)")

    glActiveTexture(GL_TEXTURE1)
    glBindTexture(GL_TEXTURE_2D, GLuint(currentMistImage.textureID))
    shader.setInt("mist_texture", value: 1)
    logger.trace("🌫️ Bound mist texture: ID \(currentMistImage.textureID)")

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
