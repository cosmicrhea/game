import NanoSVG
import Foundation

extension Image {
  // MARK: - SVG Caching
  
  /// Thread-safe cache for SVG rasterizations
  private static let svgCache = SVGCache()
  
  private final class SVGCache: @unchecked Sendable {
    private var cache: [String: Image] = [:]
    private let lock = NSLock()
    
    func get(path: String, size: Size, strokeWidth: Float?, pixelScale: Float) -> Image? {
      let key = cacheKey(path: path, size: size, strokeWidth: strokeWidth, pixelScale: pixelScale)
      lock.lock()
      defer { lock.unlock() }
      return cache[key]
    }
    
    func set(_ image: Image, path: String, size: Size, strokeWidth: Float?, pixelScale: Float) {
      let key = cacheKey(path: path, size: size, strokeWidth: strokeWidth, pixelScale: pixelScale)
      lock.lock()
      defer { lock.unlock() }
      cache[key] = image
    }
    
    private func cacheKey(path: String, size: Size, strokeWidth: Float?, pixelScale: Float) -> String {
      let stroke = strokeWidth.map { String($0) } ?? "nil"
      return "\(path):\(size.width):\(size.height):\(stroke):\(pixelScale)"
    }
  }
  
  /// Creates an image from an SVG file using NanoSVG for parsing and SVGRasterizer for rendering.
  /// - Parameters:
  ///   - svgPath: Path to the SVG file in the app bundle
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  ///   - targetSize: Optional target size for the image (default: uses SVG's natural size)
  ///   - strokeWidth: Optional stroke width override (default: nil, uses original)
  public init(svgPath: String, pixelScale: Float = 1.0, targetSize: Size? = nil, strokeWidth: Float? = nil) {
    // If targetSize is provided, we can check cache immediately
    if let targetSize = targetSize {
      if let cached = Image.svgCache.get(path: svgPath, size: targetSize, strokeWidth: strokeWidth, pixelScale: pixelScale) {
        self = cached
        return
      }
    }
    
    guard let url = Bundle.game.url(forResource: svgPath, withExtension: nil) else {
      logger.error("Image.init(svgPath:): Could not find SVG file at \(svgPath)")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    guard let data = try? Data(contentsOf: url) else {
      logger.error("Image.init(svgData:): Could not load SVG data from \(svgPath)")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    self.init(svgData: data, pixelScale: pixelScale, targetSize: targetSize, strokeWidth: strokeWidth, cacheKey: svgPath)
  }

  /// Creates an image from SVG data using NanoSVG for parsing and SVGRasterizer for rendering.
  /// - Parameters:
  ///   - svgData: Raw SVG data
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  ///   - targetSize: Optional target size for the image (default: uses SVG's natural size)
  ///   - strokeWidth: Optional stroke width override (default: nil, uses original)
  ///   - cacheKey: Optional cache key for caching (used internally when called from svgPath initializer)
  public init(svgData: Data, pixelScale: Float = 1.0, targetSize: Size? = nil, strokeWidth: Float? = nil, cacheKey: String? = nil) {
    // Preprocess SVG data to make strokes white for proper tinting
    let processedData = Image.preprocessSVGForWhiteStrokes(svgData, targetSize: targetSize, strokeWidth: strokeWidth)

    // Parse SVG using NanoSVG Swift wrapper
    guard let svgImage = SVGImage(data: processedData) else {
      logger.error("Image.init(svgData:): Failed to parse SVG data")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    // Determine target dimensions
    let targetWidth = targetSize?.width ?? svgImage.width
    let targetHeight = targetSize?.height ?? svgImage.height
    let width = Int(targetWidth)
    let height = Int(targetHeight)

    guard width > 0 && height > 0 else {
      logger.error("Image.init(svgData:): Invalid SVG dimensions")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    // Check cache if we have a cache key
    if let cacheKey = cacheKey {
      let cacheSize = Size(targetWidth, targetHeight)
      if let cached = Image.svgCache.get(path: cacheKey, size: cacheSize, strokeWidth: strokeWidth, pixelScale: pixelScale) {
        self = cached
        return
      }
    }

    // Rasterize SVG to pixels using SVGRasterizer
    let pixels = Image.rasterizeSVGWithRasterizer(svgImage: svgImage, width: width, height: height)

    logger.trace("Image.init(svgData:): Successfully loaded SVG (\(width)x\(height))")
    self = Image.uploadToGL(pixels: pixels, width: width, height: height, pixelScale: pixelScale)
    
    // Cache the result if we have a cache key
    if let cacheKey = cacheKey {
      Image.svgCache.set(self, path: cacheKey, size: Size(targetWidth, targetHeight), strokeWidth: strokeWidth, pixelScale: pixelScale)
    }
  }

  /// Rasterizes an SVG image to pixel data using SVGRasterizer
  private static func rasterizeSVGWithRasterizer(svgImage: SVGImage, width: Int, height: Int) -> [UInt8] {
    guard let rasterizer = SVGRasterizer() else {
      logger.error("Image.rasterizeSVGWithRasterizer: Failed to create SVGRasterizer")
      return Array(repeating: UInt8(0), count: width * height * 4)
    }

    guard
      let pixelData = rasterizer.rasterize(
        image: svgImage,
        width: width,
        height: height
      )
    else {
      logger.error("Image.rasterizeSVGWithRasterizer: Failed to rasterize SVG")
      return Array(repeating: UInt8(0), count: width * height * 4)
    }

    logger.trace("Image.rasterizeSVGWithRasterizer: Successfully rasterized SVG to \(width)x\(height)")
    return Array(pixelData)
  }

  /// Validates if an SVG file can be loaded and parsed
  public static func validateSVG(svgPath: String) -> Bool {
    guard let url = Bundle.game.url(forResource: svgPath, withExtension: nil) else { return false }
    guard let data = try? Data(contentsOf: url) else { return false }
    return validateSVGData(data)
  }

  /// Validates if SVG data can be parsed
  public static func validateSVGData(_ svgData: Data) -> Bool {
    return SVGImage(data: svgData) != nil
  }

  /// Preprocesses SVG data to replace black strokes with white for proper tinting
  private static func preprocessSVGForWhiteStrokes(_ svgData: Data, targetSize: Size? = nil, strokeWidth: Float? = nil)
    -> Data
  {
    guard let svgString = String(data: svgData, encoding: .utf8) else {
      return svgData
    }

    // Replace black strokes with white
    var processedString =
      svgString
      .replacingOccurrences(of: "stroke=\"black\"", with: "stroke=\"white\"")
      .replacingOccurrences(of: "stroke='black'", with: "stroke='white'")
      .replacingOccurrences(of: "fill=\"black\"", with: "fill=\"white\"")
      .replacingOccurrences(of: "fill='black'", with: "fill='white'")
      .replacingOccurrences(of: "stroke=\"currentColor\"", with: "stroke=\"white\"")
      .replacingOccurrences(of: "stroke='currentColor'", with: "stroke='white'")
      .replacingOccurrences(of: "fill=\"currentColor\"", with: "fill=\"white\"")
      .replacingOccurrences(of: "fill='currentColor'", with: "fill='white'")

    // Override or add width/height attributes based on targetSize
    if let targetSize = targetSize {
      // Add or replace width and height attributes to the SVG tag
      if let tagMatch = processedString.range(of: #"<svg[^>]*>"#, options: .regularExpression) {
        let tag = String(processedString[tagMatch])
        var newTag = tag

        // Remove existing width/height attributes if they exist
        newTag = newTag.replacingOccurrences(of: #"width="[^"]*""#, with: "", options: .regularExpression)
        newTag = newTag.replacingOccurrences(of: #"height="[^"]*""#, with: "", options: .regularExpression)
        newTag = newTag.replacingOccurrences(of: #"width='[^']*'"#, with: "", options: .regularExpression)
        newTag = newTag.replacingOccurrences(of: #"height='[^']*'"#, with: "", options: .regularExpression)

        // Add new width and height attributes
        newTag = newTag.replacingOccurrences(
          of: ">", with: " width=\"\(Int(targetSize.width))\" height=\"\(Int(targetSize.height))\">")

        processedString = processedString.replacingOccurrences(of: tag, with: newTag)
      }
    }

    // Override stroke-width if specified
    if let strokeWidth = strokeWidth {
      // Replace existing stroke-width attributes
      processedString = processedString.replacingOccurrences(
        of: #"stroke-width="[^"]*""#, with: "stroke-width=\"\(strokeWidth)\"", options: .regularExpression)
      processedString = processedString.replacingOccurrences(
        of: #"stroke-width='[^']*'"#, with: "stroke-width='\(strokeWidth)'", options: .regularExpression)

      // Add stroke-width to elements that don't have it
      processedString = processedString.replacingOccurrences(
        of: #"<path([^>]*?)(?<!stroke-width=)([^>]*?)>"#, with: "<path$1 stroke-width=\"\(strokeWidth)\"$2>",
        options: .regularExpression)
      processedString = processedString.replacingOccurrences(
        of: #"<circle([^>]*?)(?<!stroke-width=)([^>]*?)>"#, with: "<circle$1 stroke-width=\"\(strokeWidth)\"$2>",
        options: .regularExpression)
      processedString = processedString.replacingOccurrences(
        of: #"<rect([^>]*?)(?<!stroke-width=)([^>]*?)>"#, with: "<rect$1 stroke-width=\"\(strokeWidth)\"$2>",
        options: .regularExpression)
      processedString = processedString.replacingOccurrences(
        of: #"<line([^>]*?)(?<!stroke-width=)([^>]*?)>"#, with: "<line$1 stroke-width=\"\(strokeWidth)\"$2>",
        options: .regularExpression)
    }

    return processedString.data(using: .utf8) ?? svgData
  }
}
