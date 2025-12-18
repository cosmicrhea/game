import TinyEXR

extension Image {
  /// Create an Image from an EXR file path
  /// - Parameters:
  ///   - exrPath: Path to the EXR file
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  public init(exrPath: String, pixelScale: Float = 1.0) {
    self = Image.loadEXR(exrPath, pixelScale: pixelScale)
  }

  /// Create an Image from an EXR file path with a specific layer
  /// - Parameters:
  ///   - exrPath: Path to the EXR file
  ///   - layer: Name of the layer to load
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  public init(exrPath: String, layer: String, pixelScale: Float = 1.0) {
    self = Image.loadEXR(exrPath, layer: layer, pixelScale: pixelScale)
  }

  /// Load an EXR image from a file path
  /// - Parameters:
  ///   - path: Path to the EXR file
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  /// - Returns: An Image object loaded from the EXR file, or a fallback image on failure
  public static func loadEXR(_ path: String, pixelScale: Float = 1.0) -> Image {
    guard let url = Bundle.game.url(forResource: path, withExtension: nil) else {
      logger.error("Image.loadEXR: Could not find EXR file at \(path)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    return loadEXR(from: url, pixelScale: pixelScale)
  }

  /// Load an EXR image from a URL
  /// - Parameters:
  ///   - url: URL to the EXR file
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  /// - Returns: An Image object loaded from the EXR file, or a fallback image on failure
  public static func loadEXR(from url: URL, pixelScale: Float = 1.0) -> Image {
    // Try loading from memory first, as it's more reliable
    guard let data = try? Data(contentsOf: url) else {
      logger.error("Image.loadEXR: Could not read EXR file data from \(url.path)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    // Log filename for debugging (memory loading path)
    let filenameOnly = url.lastPathComponent
    logger.debug("🖼️ Loading EXR: \(filenameOnly) (from memory)")

    let memoryResult = loadEXR(from: data, pixelScale: pixelScale)

    // If memory loading fails, try direct file loading as fallback
    if memoryResult.textureID == 0 {
      logger.warning("Memory loading failed, trying direct file loading for \(url.path)")
      return loadEXRFromFile(url, pixelScale: pixelScale)
    }

    return memoryResult
  }

  /// Fallback method to load EXR directly from file
  private static func loadEXRFromFile(_ url: URL, pixelScale: Float) -> Image {
    let filename = url.path
    let cString = filename.withCString { $0 }

    var width: Int32 = 0
    var height: Int32 = 0
    var rgba: UnsafeMutablePointer<Float>? = nil
    var errorMessage: UnsafePointer<CChar>? = nil

    let result = LoadEXR(&rgba, &width, &height, cString, &errorMessage)

    defer {
      if let errorMessage = errorMessage {
        FreeEXRErrorMessage(errorMessage)
      }
    }

    guard result == TINYEXR_SUCCESS else {
      let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
      logger.error("Image.loadEXR: Failed to load EXR file at \(url.path): \(error)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    guard let rgbaData = rgba, width > 0, height > 0 else {
      logger.error("Image.loadEXR: Invalid EXR data from \(url.path)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    // EXR files are 32-bit float per channel (128 bits per pixel)
    let bitDepth = 32
    let filenameOnly = url.lastPathComponent
    logger.debug("🖼️ Loading EXR: \(filenameOnly) - \(width)x\(height), \(bitDepth)-bit float per channel")

    // Convert to array format for upload (preserve full precision, no tone mapping/gamma)
    let pixelCount = Int(width * height)
    var floatPixels: [Float] = []
    floatPixels.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      floatPixels.append(rgbaData[i * 4 + 0])  // R
      floatPixels.append(rgbaData[i * 4 + 1])  // G
      floatPixels.append(rgbaData[i * 4 + 2])  // B
      floatPixels.append(rgbaData[i * 4 + 3])  // A
    }

    logger.trace("Decoded EXR image from file: \(width)x\(height), preserving full float precision")

    return Image.uploadToGLFloat(
      pixels: floatPixels,
      width: Int(width),
      height: Int(height),
      pixelScale: pixelScale
    )
  }

  /// Load an EXR image from memory data
  /// - Parameters:
  ///   - data: EXR file data
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  /// - Returns: An Image object loaded from the EXR data, or a fallback image on failure
  public static func loadEXR(from data: Data, pixelScale: Float = 1.0) -> Image {
    let dataBytes = Array(data)

    var width: Int32 = 0
    var height: Int32 = 0
    var rgba: UnsafeMutablePointer<Float>? = nil
    var errorMessage: UnsafePointer<CChar>? = nil

    let result = dataBytes.withUnsafeBytes { rawBytes in
      LoadEXRFromMemory(
        &rgba, &width, &height, rawBytes.bindMemory(to: UInt8.self).baseAddress!, rawBytes.count, &errorMessage)
    }

    defer {
      if let errorMessage = errorMessage {
        FreeEXRErrorMessage(errorMessage)
      }
    }

    guard result == TINYEXR_SUCCESS else {
      let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
      logger.error("Image.loadEXR: Failed to load EXR data: \(error)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    guard let rgbaData = rgba, width > 0, height > 0 else {
      logger.error("Image.loadEXR: Invalid EXR data")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    // EXR files are 32-bit float per channel (128 bits per pixel)
    let bitDepth = 32
    logger.debug("🖼️ Loading EXR from memory - \(width)x\(height), \(bitDepth)-bit float per channel")

    // Convert to array format for upload (preserve full precision, no tone mapping/gamma)
    let pixelCount = Int(width * height)
    var floatPixels: [Float] = []
    floatPixels.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      floatPixels.append(rgbaData[i * 4 + 0])  // R
      floatPixels.append(rgbaData[i * 4 + 1])  // G
      floatPixels.append(rgbaData[i * 4 + 2])  // B
      floatPixels.append(rgbaData[i * 4 + 3])  // A
    }

    logger.trace("Decoded EXR image: \(width)x\(height), preserving full float precision")

    return Image.uploadToGLFloat(
      pixels: floatPixels,
      width: Int(width),
      height: Int(height),
      pixelScale: pixelScale
    )
  }

  /// Load an EXR image with a specific layer
  /// - Parameters:
  ///   - path: Path to the EXR file
  ///   - layerName: Name of the layer to load
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  /// - Returns: An Image object loaded from the specified layer, or a fallback image on failure
  public static func loadEXR(_ path: String, layer layerName: String, pixelScale: Float = 1.0) -> Image {
    guard let url = Bundle.game.url(forResource: path, withExtension: nil) else {
      logger.error("Image.loadEXR: Could not find EXR file at \(path)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    return loadEXR(from: url, layer: layerName, pixelScale: pixelScale)
  }

  /// Load an EXR image with a specific layer from a URL
  /// - Parameters:
  ///   - url: URL to the EXR file
  ///   - layerName: Name of the layer to load
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  /// - Returns: An Image object loaded from the specified layer, or a fallback image on failure
  public static func loadEXR(from url: URL, layer layerName: String, pixelScale: Float = 1.0) -> Image {
    let filename = url.path
    let cString = filename.withCString { $0 }
    let layerCString = layerName.withCString { $0 }

    var width: Int32 = 0
    var height: Int32 = 0
    var rgba: UnsafeMutablePointer<Float>? = nil
    var errorMessage: UnsafePointer<CChar>? = nil

    let result = LoadEXRWithLayer(&rgba, &width, &height, cString, layerCString, &errorMessage)

    defer {
      if let errorMessage = errorMessage {
        FreeEXRErrorMessage(errorMessage)
      }
    }

    guard result == TINYEXR_SUCCESS else {
      let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
      logger.error("Image.loadEXR: Failed to load EXR layer '\(layerName)' from \(url.path): \(error)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    guard let rgbaData = rgba, width > 0, height > 0 else {
      logger.error("Image.loadEXR: Invalid EXR layer data from \(url.path)")
      return Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
    }

    // EXR files are 32-bit float per channel (128 bits per pixel)
    let bitDepth = 32
    let filenameOnly = url.lastPathComponent
    logger.debug("🖼️ Loading EXR layer '\(layerName)' from \(filenameOnly) - \(width)x\(height), \(bitDepth)-bit float per channel")

    // Convert to array format for upload (preserve full precision, no tone mapping/gamma)
    let pixelCount = Int(width * height)
    var floatPixels: [Float] = []
    floatPixels.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      floatPixels.append(rgbaData[i * 4 + 0])  // R
      floatPixels.append(rgbaData[i * 4 + 1])  // G
      floatPixels.append(rgbaData[i * 4 + 2])  // B
      floatPixels.append(rgbaData[i * 4 + 3])  // A
    }

    logger.trace("Decoded EXR layer '\(layerName)' at \(url.path): \(width)x\(height), preserving full float precision")

    return Image.uploadToGLFloat(
      pixels: floatPixels,
      width: Int(width),
      height: Int(height),
      pixelScale: pixelScale
    )
  }

  /// Get available layer names from an EXR file
  /// - Parameter path: Path to the EXR file
  /// - Returns: Array of layer names, or empty array on failure
  public static func getEXRLayers(_ path: String) -> [String] {
    guard let url = Bundle.game.url(forResource: path, withExtension: nil) else {
      logger.error("Image.getEXRLayers: Could not find EXR file at \(path)")
      return []
    }

    let filename = url.path
    let cString = filename.withCString { $0 }

    var layerNames: UnsafeMutablePointer<UnsafePointer<CChar>?>? = nil
    var numLayers: Int32 = 0
    var errorMessage: UnsafePointer<CChar>? = nil

    let result = EXRLayers(cString, &layerNames, &numLayers, &errorMessage)

    defer {
      if let errorMessage = errorMessage {
        FreeEXRErrorMessage(errorMessage)
      }
    }

    guard result == TINYEXR_SUCCESS, let layers = layerNames, numLayers > 0 else {
      let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
      logger.error("Image.getEXRLayers: Failed to get layers from \(path): \(error)")
      return []
    }

    var layerNamesArray: [String] = []
    for i in 0..<Int(numLayers) {
      if let layerName = layers[i] {
        layerNamesArray.append(String(cString: layerName))
      }
    }

    logger.trace("Found \(numLayers) layers in \(path): \(layerNamesArray)")
    return layerNamesArray
  }

}
