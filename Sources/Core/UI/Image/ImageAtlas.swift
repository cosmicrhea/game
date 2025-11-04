/// A single entry in an image atlas, representing a subimage within a larger texture.
public struct ImageAtlasEntry {
  /// The name identifier for this atlas entry.
  public let name: String
  /// Normalized UV coordinates [0,1] within the atlas texture.
  public let uv: Rect
  /// Pixel size of the subimage.
  public let size: Size
}

/// A collection of subimages packed into a single texture for efficient rendering.
public final class ImageAtlas {
  /// The underlying texture containing all subimages.
  public let texture: Image
  public let entries: [String: ImageAtlasEntry]

  /// Creates an image atlas from a texture and a collection of entries.
  /// - Parameters:
  ///   - texture: The texture containing all subimages.
  ///   - entries: Array of atlas entries defining subimage locations and sizes.
  public init(texture: Image, entries: [ImageAtlasEntry]) {
    self.texture = texture
    var map: [String: ImageAtlasEntry] = [:]
    for e in entries { map[e.name] = e }
    self.entries = map
  }

  /// Returns the atlas entry with the specified name.
  /// - Parameter name: The name of the atlas entry to retrieve.
  /// - Returns: The atlas entry, or `nil` if not found.
  public func entry(named name: String) -> ImageAtlasEntry? { entries[name] }

  /// Draws a subimage from the atlas in the specified rectangle.
  /// - Parameters:
  ///   - name: The name of the atlas entry to draw.
  ///   - rect: Destination rectangle in points.
  ///   - tint: Optional color tint to apply; defaults to `nil` (no tint).
  ///   - strokeWidth: Optional stroke width in points. If 0 or nil, no stroke is applied.
  ///   - strokeColor: Optional stroke color. Ignored if strokeWidth is 0 or nil.
  ///   - context: Target `GraphicsContext`; defaults to `GraphicsContext.current`.
  public func draw(
    name: String,
    in rect: Rect,
    tint: Color? = nil,
    strokeWidth: Float? = nil,
    strokeColor: Color? = nil,
    context: GraphicsContext? = nil
  ) {
    guard let entry = entries[name] else {
      logger.error("ImageAtlas.draw: entry '\(name)' not found")
      return
    }

    let ctx = context ?? GraphicsContext.current
    guard let ctx else {
      logger.error("ImageAtlas.draw: no GraphicsContext")
      return
    }

    //logger.trace("ImageAtlas.draw: drawing '\(name)' at \(rect) with UV \(entry.uv)")
    ctx.renderer.drawImageRegion(
      textureID: texture.textureID,
      in: rect,
      uv: entry.uv,
      tint: tint,
      strokeWidth: strokeWidth ?? 0,
      strokeColor: strokeColor
    )
  }

  // MARK: - InputPrompts convenience
  nonisolated(unsafe) private static var inputPromptCache: [InputSource: ImageAtlas] = [:]

  /// Loads the input prompts atlas for the specified input source.
  /// - Parameter source: The input source to load the atlas for.
  /// - Returns: The loaded atlas, or `nil` if loading failed.
  public static func loadInputPromptsAtlas(for source: InputSource?) -> ImageAtlas? {
    let src = source ?? .keyboardMouse
    if let cached = inputPromptCache[src] {
      logger.debug("ImageAtlas: using cached atlas for \(src)")
      return cached
    }
    //logger.trace("ImageAtlas: loading new atlas for \(src)")
    let path = src.inputPromptAtlasPath
    if let atlas = ImageAtlas(tpxmlPath: path) {
      inputPromptCache[src] = atlas
      //logger.trace("ImageAtlas: cached atlas for \(src)")
      return atlas
    }
    logger.error("ImageAtlas: failed to load atlas for \(src) at path \(path)")
    return nil
  }
}
