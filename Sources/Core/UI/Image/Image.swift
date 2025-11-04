import ImageFormats

/// An object that manages image data in the game.
public struct Image: Sendable {
  public let textureID: UInt64
  public let naturalSize: Size
  public let pixelScale: Float
  let framebufferID: UInt64?

  // If non-nil, this Image instance owns the GL texture lifetime
  private let textureHandle: GLTextureHandle?

  let pixelBytes: [UInt8]?
  let pixelWidth: Int
  let pixelHeight: Int

  /// Creates an image from a texture ID, natural size, and pixel scale.
  public init(textureID: UInt64, naturalSize: Size, pixelScale: Float = 1.0, framebufferID: UInt64? = nil) {
    self.textureID = textureID
    self.naturalSize = naturalSize
    self.pixelScale = pixelScale
    self.framebufferID = framebufferID
    self.textureHandle = nil
    self.pixelBytes = nil
    self.pixelWidth = Int(naturalSize.width)
    self.pixelHeight = Int(naturalSize.height)
  }

  /// Creates an image from raw RGBA8 pixels.
  public init(pixels: [UInt8], width: Int, height: Int, pixelScale: Float = 1.0) {
    self.textureID = 0
    self.naturalSize = Size(Float(width), Float(height))
    self.pixelScale = pixelScale
    self.framebufferID = nil
    self.textureHandle = nil
    self.pixelBytes = pixels
    self.pixelWidth = width
    self.pixelHeight = height
  }

  init(
    textureID: UInt64, naturalSize: Size, pixelScale: Float, framebufferID: UInt64?, pixelBytes: [UInt8]?,
    pixelWidth: Int, pixelHeight: Int
  ) {
    self.textureID = textureID
    self.naturalSize = naturalSize
    self.pixelScale = pixelScale
    self.framebufferID = framebufferID
    self.textureHandle = nil
    self.pixelBytes = pixelBytes
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
  }

  // Internal initializer for adopting an existing GLTextureHandle
  init(handle: GLTextureHandle, naturalSize: Size, pixelScale: Float) {
    self.textureID = UInt64(handle.id)
    self.naturalSize = naturalSize
    self.pixelScale = pixelScale
    self.framebufferID = nil
    self.textureHandle = handle
    self.pixelBytes = nil
    self.pixelWidth = Int(naturalSize.width)
    self.pixelHeight = Int(naturalSize.height)
  }

  /// Draws the image at the specified point, optionally specifying a size.
  /// - Parameters:
  ///   - point: Destination origin in points.
  ///   - size: Optional draw size; defaults to `naturalSize`.
  ///   - tint: Optional color tint to apply to the image.
  ///   - strokeWidth: Optional stroke width in points. If 0 or nil, no stroke is applied.
  ///   - strokeColor: Optional stroke color. Ignored if strokeWidth is 0 or nil.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    at point: Point,
    size: Size? = nil,
    tint: Color? = nil,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil,
    context: GraphicsContext? = nil
  ) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }
    guard textureID != 0 else { return }
    let drawSize = size ?? naturalSize

    // Hack: Framebuffer-backed images need Y-flip due to OpenGL coordinate system differences
    let adjustedRect: Rect
    if framebufferID != nil {
      // Flip Y coordinate for framebuffer-backed images
      adjustedRect = Rect(
        x: point.x,
        y: point.y,
        width: drawSize.width,
        height: -drawSize.height
      )
    } else {
      adjustedRect = Rect(origin: point, size: drawSize)
    }

    ctx.renderer.drawImage(
      textureID: textureID,
      in: adjustedRect,
      tint: tint,
      strokeWidth: strokeWidth ?? 0,
      strokeColor: strokeColor
    )
  }

  /// Draws the image in the specified rectangle.
  /// - Parameters:
  ///   - rect: Destination rectangle in points.
  ///   - tint: Optional color tint to apply to the image.
  ///   - strokeWidth: Optional stroke width in points. If 0 or nil, no stroke is applied.
  ///   - strokeColor: Optional stroke color. Ignored if strokeWidth is 0 or nil.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    in rect: Rect,
    tint: Color? = nil,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil,
    context: GraphicsContext? = nil
  ) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }
    guard textureID != 0 else { return }

    // Framebuffer-backed images need Y-flip due to OpenGL coordinate system differences
    let adjustedRect: Rect
    if framebufferID != nil {
      // Flip Y coordinate for framebuffer-backed images
      adjustedRect = Rect(
        x: rect.minX,
        y: rect.minY,
        width: rect.width,
        height: -rect.height
      )
    } else {
      adjustedRect = rect
    }

    ctx.renderer.drawImage(
      textureID: textureID,
      in: adjustedRect,
      tint: tint,
      strokeWidth: strokeWidth ?? 0,
      strokeColor: strokeColor
    )
  }

  /// Draws the image in the specified rectangle with rotation and scale applied around the rect center.
  /// - Parameters:
  ///   - rect: Destination rectangle in points.
  ///   - rotation: Rotation in radians, applied around rect center.
  ///   - scale: Optional scale (default 1,1), applied around rect center.
  ///   - tint: Optional color tint.
  ///   - strokeWidth: Optional stroke width in points. If 0 or nil, no stroke is applied.
  ///   - strokeColor: Optional stroke color. Ignored if strokeWidth is 0 or nil.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    in rect: Rect,
    rotation: Float,
    scale: Point = Point(1, 1),
    tint: Color? = nil,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil,
    context: GraphicsContext? = nil
  ) {
    let ctx = context ?? GraphicsContext.current
    guard let ctx else { return }
    guard textureID != 0 else { return }

    // Framebuffer-backed images need Y-flip due to OpenGL coordinate system differences
    let adjustedRect: Rect
    if framebufferID != nil {
      adjustedRect = Rect(
        x: rect.minX,
        y: rect.minY,
        width: rect.width,
        height: -rect.height
      )
    } else {
      adjustedRect = rect
    }

    ctx.renderer.drawImageTransformed(
      textureID: textureID,
      in: adjustedRect,
      rotation: rotation,
      scale: scale,
      tint: tint,
      strokeWidth: strokeWidth ?? 0,
      strokeColor: strokeColor
    )
  }

  /// Draws the image at a point with optional size, rotation, and scale.
  /// Note: Rotation is applied around the center of the destination rect.
  public func draw(
    at point: Point,
    size: Size? = nil,
    rotation: Float,
    scale: Point = Point(1, 1),
    tint: Color? = nil,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil,
    context: GraphicsContext? = nil
  ) {
    let drawSize = size ?? naturalSize
    let rect = Rect(origin: point, size: drawSize)
    draw(
      in: rect,
      rotation: rotation,
      scale: scale,
      tint: tint,
      strokeWidth: strokeWidth,
      strokeColor: strokeColor,
      context: context
    )
  }

  /// Writes the image to a PNG file.
  /// - Parameter filePath: The path to save the PNG file to.
  public func write(toFile filePath: String) throws {
    let width = Int(naturalSize.width)
    let height = Int(naturalSize.height)

    // Store the currently bound framebuffer
    var previousFBO: GLint = 0
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFBO)

    var fboToRead: GLuint = 0
    var createdTempFBO = false

    if let framebufferID = framebufferID {
      fboToRead = GLuint(framebufferID)
    } else {
      // Create a temporary FBO and attach our texture so we can read back
      createdTempFBO = true
      glGenFramebuffers(1, &fboToRead)
      glBindFramebuffer(GL_FRAMEBUFFER, fboToRead)
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, GLuint(textureID), 0)
    }

    // If not created temp FBO from above, bind the existing one for readback
    if !createdTempFBO {
      glBindFramebuffer(GL_FRAMEBUFFER, fboToRead)
    }

    // Read pixels from the framebuffer
    var pixelBytes = [UInt8](repeating: 0, count: width * height * 4)
    glPixelStorei(GL_PACK_ALIGNMENT, 1)
    glReadBuffer(GL_COLOR_ATTACHMENT0)
    pixelBytes.withUnsafeMutableBytes { rawBuffer in
      if let base = rawBuffer.baseAddress {
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GL_RGBA, GL_UNSIGNED_BYTE, base)
      }
    }

    // Cleanup temporary FBO if we created one
    if createdTempFBO {
      var delFBO = fboToRead
      glDeleteFramebuffers(1, &delFBO)
    }

    // Restore previous FBO binding
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(previousFBO))

    // Flip rows to convert from OpenGL's bottom-left origin to top-left
    let rowStride = width * 4
    var flipped = [UInt8](repeating: 0, count: pixelBytes.count)
    for row in 0..<height {
      let srcStart = row * rowStride
      let dstStart = (height - 1 - row) * rowStride
      flipped[dstStart..<(dstStart + rowStride)] = pixelBytes[srcStart..<(srcStart + rowStride)]
    }

    // Save as PNG
    let imageFormatsImage = ImageFormats.Image<ImageFormats.RGBA>(width: width, height: height, bytes: flipped)
    let pngBytes = try imageFormatsImage.encodeToPNG()
    try Data(pngBytes).write(to: URL(fileURLWithPath: filePath))
  }
}

public enum ImageError: Error {
  case noFramebufferAvailable
}
