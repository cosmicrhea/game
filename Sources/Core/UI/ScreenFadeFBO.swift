/// A proper FBO-based screen fade system for transitions
@MainActor
public final class ScreenFadeFBO {
  public static let shared = ScreenFadeFBO()

  private var currentOpacity: Float = 0.0
  private var targetOpacity: Float = 0.0
  private var startOpacity: Float = 0.0
  private var animationTime: Float = 0.0
  private var isAnimating: Bool = false
  private var animationDuration: Float = 0.3
  private let animationEasing: Easing = .easeInOutCubic

  // FBO for capturing the screen
  private var fbo: GLuint = 0
  private var colorTexture: GLuint = 0
  private var depthBuffer: GLuint = 0
  private var width: Int = 0
  private var height: Int = 0
  private var isInitialized: Bool = false

  // Shader for the fade effect
  private var fadeShader: GLProgram?

  private init() {}

  deinit {
    // Note: cleanup will be called when the object is deallocated
    // The OpenGL resources will be cleaned up by the system
  }

  /// Start a fade to black transition
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  /// - Parameter completion: Optional callback when fade completes
  public func fadeToBlack(duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = 1.0
    animationDuration = duration
    startAnimation(completion: completion)

    // Capture the current screen when starting a fade
    captureCurrentScreen()
  }

  /// Start a fade to black transition (async version)
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  public func fadeToBlack(duration: Float = 0.3) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      fadeToBlack(duration: duration) {
        continuation.resume()
      }
    }
  }

  /// Start a fade from black transition
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  /// - Parameter completion: Optional callback when fade completes
  public func fadeFromBlack(duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = 0.0
    animationDuration = duration
    startAnimation(completion: completion)
  }

  /// Start a fade from black transition (async version)
  /// - Parameter duration: How long the fade should take (default: 0.3 seconds)
  public func fadeFromBlack(duration: Float = 0.3) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      fadeFromBlack(duration: duration) {
        continuation.resume()
      }
    }
  }

  /// Start a fade to a specific opacity
  /// - Parameters:
  ///   - opacity: Target opacity (0.0 = transparent, 1.0 = opaque)
  ///   - duration: How long the fade should take
  ///   - completion: Optional callback when fade completes
  public func fadeToOpacity(_ opacity: Float, duration: Float = 0.3, completion: (() -> Void)? = nil) {
    targetOpacity = opacity
    animationDuration = duration
    startAnimation(completion: completion)
  }

  /// Check if the overlay is currently visible (opacity > 0)
  public var isVisible: Bool {
    return currentOpacity > 0.0
  }

  /// Get the current opacity value
  public var opacity: Float {
    return currentOpacity
  }

  /// Reset the fade to transparent state
  public func reset() {
    currentOpacity = 0.0
    targetOpacity = 0.0
    startOpacity = 0.0
    isAnimating = false
    animationTime = 0.0
    completionCallback = nil
  }

  /// Update the fade animation
  /// - Parameter deltaTime: Time since last frame
  public func update(deltaTime: Float) {
    guard isAnimating else { return }

    animationTime += deltaTime
    let progress = min(animationTime / animationDuration, 1.0)
    let easedProgress = animationEasing.apply(progress)

    // Interpolate between start and target opacity
    currentOpacity = startOpacity + (targetOpacity - startOpacity) * easedProgress

    if progress >= 1.0 {
      isAnimating = false
      animationTime = 0.0
      currentOpacity = targetOpacity
      completionCallback?()
      completionCallback = nil
    }
  }

  /// Capture the current screen content to FBO
  private func captureCurrentScreen() {
    // Get current viewport size
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
    let newWidth = Int(viewport[2])
    let newHeight = Int(viewport[3])

    // Recreate FBO if size changed
    if newWidth != width || newHeight != height {
      cleanup()
      setupFBO(width: newWidth, height: newHeight)
    }

    // Copy current back buffer to our FBO texture
    glBindTexture(GL_TEXTURE_2D, colorTexture)
    glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, GLsizei(width), GLsizei(height))
    glBindTexture(GL_TEXTURE_2D, 0)
  }

  /// Draw the fade overlay using the captured screen
  /// - Parameters:
  ///   - screenSize: The size of the screen to cover
  public func draw(screenSize: Size) {
    guard currentOpacity > 0.0 else { return }
    guard isInitialized else { return }

    // Unbind FBO and return to default framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    glViewport(0, 0, GLsizei(screenSize.width), GLsizei(screenSize.height))

    // Use the fade shader
    guard let shader = fadeShader else { return }
    shader.use()

    // Set the captured texture
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, colorTexture)
    shader.setInt("uTexture", value: 0)

    // Set the fade opacity
    shader.setFloat("uOpacity", value: currentOpacity)

    // Draw a fullscreen quad
    drawFullscreenQuad()
  }

  // MARK: - Private

  private var completionCallback: (() -> Void)?

  private func startAnimation(completion: (() -> Void)?) {
    startOpacity = currentOpacity
    isAnimating = true
    animationTime = 0.0
    completionCallback = completion
  }

  private func setupFBO(width: Int, height: Int) {
    // Validate dimensions
    if width <= 0 || height <= 0 {
      logger.error("ERROR: Invalid FBO dimensions: \(width)x\(height)")
      return
    }

    self.width = width
    self.height = height

    // Generate FBO
    glGenFramebuffers(1, &fbo)
    glBindFramebuffer(GL_FRAMEBUFFER, fbo)

    // Generate color texture
    glGenTextures(1, &colorTexture)
    glBindTexture(GL_TEXTURE_2D, colorTexture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    // Attach color texture to FBO
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, colorTexture, 0)

    // Generate depth buffer
    glGenRenderbuffers(1, &depthBuffer)
    glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer)
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, GLsizei(width), GLsizei(height))
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthBuffer)

    // Check FBO status
    let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
    if status != GL_FRAMEBUFFER_COMPLETE {
      logger.error("ERROR: FBO not complete: \(status)")
      cleanup()
      return
    }

    // Create fade shader
    do {
      fadeShader = try GLProgram("Common/Passthrough", "Effects/fade")
    } catch {
      logger.error("ERROR: Failed to create fade shader: \(error)")
    }

    isInitialized = true
  }

  private func cleanup() {
    if fbo != 0 {
      glDeleteFramebuffers(1, &fbo)
      fbo = 0
    }
    if colorTexture != 0 {
      glDeleteTextures(1, &colorTexture)
      colorTexture = 0
    }
    if depthBuffer != 0 {
      glDeleteRenderbuffers(1, &depthBuffer)
      depthBuffer = 0
    }
    isInitialized = false
  }

  private func drawFullscreenQuad() {
    // Simple fullscreen quad vertices
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

    // Create VAO and VBO
    var vao: GLuint = 0
    var vbo: GLuint = 0
    var ebo: GLuint = 0

    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)
    glGenBuffers(1, &ebo)

    glBindVertexArray(vao)

    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.count * MemoryLayout<UInt32>.stride, indices, GL_STATIC_DRAW)

    // Position attribute
    glVertexAttribPointer(0, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride), nil)
    glEnableVertexAttribArray(0)

    // Texture coordinate attribute
    glVertexAttribPointer(
      1, 2, GL_FLOAT, false, GLsizei(4 * MemoryLayout<Float>.stride),
      UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride))
    glEnableVertexAttribArray(1)

    // Draw the quad
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, nil)

    // Cleanup
    glDeleteVertexArrays(1, &vao)
    glDeleteBuffers(1, &vbo)
    glDeleteBuffers(1, &ebo)
  }
}
