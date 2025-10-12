/// An object that manages image data in the game.
public struct Image: Sendable {
  public let textureID: UInt64
  public let naturalSize: Size
  public let pixelScale: Float

  let pixelBytes: [UInt8]?
  let pixelWidth: Int
  let pixelHeight: Int

  /// Creates an image from a texture ID, natural size, and pixel scale.
  public init(textureID: UInt64, naturalSize: Size, pixelScale: Float = 1.0) {
    self.textureID = textureID
    self.naturalSize = naturalSize
    self.pixelScale = pixelScale
    self.pixelBytes = nil
    self.pixelWidth = Int(naturalSize.width)
    self.pixelHeight = Int(naturalSize.height)
  }

  /// Creates an image from raw RGBA8 pixels.
  public init(pixels: [UInt8], width: Int, height: Int, pixelScale: Float = 1.0) {
    self.textureID = 0
    self.naturalSize = Size(Float(width), Float(height))
    self.pixelScale = pixelScale
    self.pixelBytes = pixels
    self.pixelWidth = width
    self.pixelHeight = height
  }

  init(textureID: UInt64, naturalSize: Size, pixelScale: Float, pixelBytes: [UInt8]?, pixelWidth: Int, pixelHeight: Int)
  {
    self.textureID = textureID
    self.naturalSize = naturalSize
    self.pixelScale = pixelScale
    self.pixelBytes = pixelBytes
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
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
    ctx.renderer.drawImage(
      textureID: textureID,
      in: Rect(origin: point, size: drawSize),
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
    ctx.renderer.drawImage(
      textureID: textureID,
      in: rect,
      tint: tint
    )
  }
}
