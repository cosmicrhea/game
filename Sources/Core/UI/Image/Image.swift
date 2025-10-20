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
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(at point: Point, size: Size? = nil, context: GraphicsContext? = nil) {
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
      tint: nil
    )
  }

  /// Draws the image in the specified rectangle.
  /// - Parameters:
  ///   - rect: Destination rectangle in points.
  ///   - tint:
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(in rect: Rect, tint: Color? = nil, context: GraphicsContext? = nil) {
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
      tint: tint
    )
  }

  /// Writes the image to a PNG file.
  /// - Parameter filePath: The path to save the PNG file to.
  public func write(toFile filePath: String) throws {
    guard let framebufferID = framebufferID else {
      throw ImageError.noFramebufferAvailable
    }

    let width = Int(naturalSize.width)
    let height = Int(naturalSize.height)

    // Store the currently bound framebuffer
    var currentFramebuffer: GLint = 0
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &currentFramebuffer)

    // Bind our framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(framebufferID))

    // Read pixels from the framebuffer
    var pixelBytes = [UInt8](repeating: 0, count: width * height * 4)
    glPixelStorei(GL_PACK_ALIGNMENT, 1)
    glReadBuffer(GL_COLOR_ATTACHMENT0)
    pixelBytes.withUnsafeMutableBytes { rawBuffer in
      if let base = rawBuffer.baseAddress {
        glReadPixels(0, 0, GLsizei(width), GLsizei(height), GL_RGBA, GL_UNSIGNED_BYTE, base)
      }
    }

    // Restore the previously bound framebuffer
    glBindFramebuffer(GL_FRAMEBUFFER, GLuint(currentFramebuffer))

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
