import Foundation
import NanoSVG

extension Image {
  /// Creates an image from an SVG file using NanoSVG for parsing and SVGRasterizer for rendering.
  /// - Parameters:
  ///   - svgPath: Path to the SVG file in the app bundle
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  ///   - targetSize: Optional target size for the image (default: uses SVG's natural size)
  public init(svgPath: String, pixelScale: Float = 1.0, targetSize: Size? = nil) {
    guard let url = Bundle.module.url(forResource: svgPath, withExtension: nil) else {
      logger.error("Image.init(svgPath:): Could not find SVG file at \(svgPath)")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    guard let data = try? Data(contentsOf: url) else {
      logger.error("Image.init(svgData:): Could not load SVG data from \(svgPath)")
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    self.init(svgData: data, pixelScale: pixelScale, targetSize: targetSize)
  }

  /// Creates an image from SVG data using NanoSVG for parsing and SVGRasterizer for rendering.
  /// - Parameters:
  ///   - svgData: Raw SVG data
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  ///   - targetSize: Optional target size for the image (default: uses SVG's natural size)
  public init(svgData: Data, pixelScale: Float = 1.0, targetSize: Size? = nil) {
    // Preprocess SVG data to make strokes white for proper tinting
    let processedData = Image.preprocessSVGForWhiteStrokes(svgData)

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

    // Rasterize SVG to pixels using SVGRasterizer
    let pixels = Image.rasterizeSVGWithRasterizer(svgImage: svgImage, width: width, height: height)

    logger.trace("Image.init(svgData:): Successfully loaded SVG (\(width)x\(height))")
    self = Image.uploadToGL(pixels: pixels, width: width, height: height, pixelScale: pixelScale)
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
    guard let url = Bundle.module.url(forResource: svgPath, withExtension: nil) else { return false }
    guard let data = try? Data(contentsOf: url) else { return false }
    return validateSVGData(data)
  }

  /// Validates if SVG data can be parsed
  public static func validateSVGData(_ svgData: Data) -> Bool {
    return SVGImage(data: svgData) != nil
  }

  /// Preprocesses SVG data to replace black strokes with white for proper tinting
  private static func preprocessSVGForWhiteStrokes(_ svgData: Data) -> Data {
    guard let svgString = String(data: svgData, encoding: .utf8) else {
      return svgData
    }

    // Replace black strokes with white
    let processedString =
      svgString
      .replacingOccurrences(of: "stroke=\"black\"", with: "stroke=\"white\"")
      .replacingOccurrences(of: "stroke='black'", with: "stroke='white'")
      .replacingOccurrences(of: "fill=\"black\"", with: "fill=\"white\"")
      .replacingOccurrences(of: "fill='black'", with: "fill='white'")

    return processedString.data(using: .utf8) ?? svgData
  }
}
