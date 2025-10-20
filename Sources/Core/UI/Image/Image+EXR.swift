import Foundation
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
    guard let url = Bundle.module.url(forResource: path, withExtension: nil) else {
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

    // Convert float RGBA data to UInt8 RGBA8
    let pixelCount = Int(width * height)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      let r = rgbaData[i * 4 + 0]
      let g = rgbaData[i * 4 + 1]
      let b = rgbaData[i * 4 + 2]
      let a = rgbaData[i * 4 + 3]

      // Convert from float [0,1] to UInt8 [0,255]
      // Apply tone mapping for HDR values
      let toneMappedR = performToneMapping(r)
      let toneMappedG = performToneMapping(g)
      let toneMappedB = performToneMapping(b)
      let toneMappedA = performToneMapping(a)

      bytes.append(UInt8(max(0, min(255, toneMappedR * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedG * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedB * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedA * 255))))
    }

    logger.trace("Decoded EXR image from file: \(width)x\(height)")

    return Image.uploadToGL(
      pixels: bytes,
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

    // Convert float RGBA data to UInt8 RGBA8
    let pixelCount = Int(width * height)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      let r = rgbaData[i * 4 + 0]
      let g = rgbaData[i * 4 + 1]
      let b = rgbaData[i * 4 + 2]
      let a = rgbaData[i * 4 + 3]

      // Convert from float [0,1] to UInt8 [0,255]
      // Apply tone mapping for HDR values
      let toneMappedR = performToneMapping(r)
      let toneMappedG = performToneMapping(g)
      let toneMappedB = performToneMapping(b)
      let toneMappedA = performToneMapping(a)

      bytes.append(UInt8(max(0, min(255, toneMappedR * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedG * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedB * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedA * 255))))
    }

    logger.trace("Decoded EXR image: \(width)x\(height)")

    return Image.uploadToGL(
      pixels: bytes,
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
    guard let url = Bundle.module.url(forResource: path, withExtension: nil) else {
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

    // Convert float RGBA data to UInt8 RGBA8
    let pixelCount = Int(width * height)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(pixelCount * 4)

    for i in 0..<pixelCount {
      let r = rgbaData[i * 4 + 0]
      let g = rgbaData[i * 4 + 1]
      let b = rgbaData[i * 4 + 2]
      let a = rgbaData[i * 4 + 3]

      // Convert from float [0,1] to UInt8 [0,255]
      // Apply tone mapping for HDR values
      let toneMappedR = performToneMapping(r)
      let toneMappedG = performToneMapping(g)
      let toneMappedB = performToneMapping(b)
      let toneMappedA = performToneMapping(a)

      bytes.append(UInt8(max(0, min(255, toneMappedR * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedG * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedB * 255))))
      bytes.append(UInt8(max(0, min(255, toneMappedA * 255))))
    }

    logger.trace("Decoded EXR layer '\(layerName)' at \(url.path): \(width)x\(height)")

    return Image.uploadToGL(
      pixels: bytes,
      width: Int(width),
      height: Int(height),
      pixelScale: pixelScale
    )
  }

  /// Get available layer names from an EXR file
  /// - Parameter path: Path to the EXR file
  /// - Returns: Array of layer names, or empty array on failure
  public static func getEXRLayers(_ path: String) -> [String] {
    guard let url = Bundle.module.url(forResource: path, withExtension: nil) else {
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

  /// Simple tone mapping function for HDR values
  /// - Parameter value: Input float value (can be > 1.0 for HDR)
  /// - Returns: Tone-mapped value in [0,1] range
  private static func performToneMapping(_ value: Float) -> Float {
    // Simple Reinhard tone mapping: x / (1 + x)
    return value / (1.0 + value)
  }
}
