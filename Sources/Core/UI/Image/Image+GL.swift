import GL

import class Foundation.Bundle
import struct Foundation.Data
import class Foundation.FileManager
import struct Foundation.URL
import struct ImageFormats.Image
import struct ImageFormats.RGBA

extension Image {
  /// Load an image from SPM resource path and upload to GL. Returns a GPU-backed Image.
  public init(_ path: String, size: Size? = nil, strokeWidth: Float? = nil, pixelScale: Float = 1.0) {
    var width = 1
    var height = 1
    var bytes: [UInt8] = [255, 255, 255, 255]

    if let baseURL = Bundle.module.resourceURL {
      let url = baseURL.appendingPathComponent(path)
      if let data = try? Data(contentsOf: url) {
        let ext = url.pathExtension.lowercased()
        let raw = Array(data)
        let loaded: ImageFormats.Image<ImageFormats.RGBA>?
        if ext == "png" {
          loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: raw)
        } else if ext == "webp" {
          loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: raw)
        } else {
          loaded = try? ImageFormats.Image<ImageFormats.RGBA>.load(from: raw)
        }
        if let image = loaded {
          logger.trace("Decoded image at \(path)")
          width = image.width
          height = image.height
          bytes = image.bytes
        } else {
          logger.error("Failed to decode image at \(path)")
        }
      } else {
        logger.error("Failed to load image at \(path)")
      }
    }

    self = Image.uploadToGL(pixels: bytes, width: width, height: height, pixelScale: pixelScale)
  }

  /// Upload RGBA8 pixels to GL and return a GPU-backed Image.
  public static func uploadToGL(pixels: [UInt8], width: Int, height: Int, pixelScale: Float = 1.0) -> Image {
    var tex: GLuint = 0
    glGenTextures(1, &tex)
    glBindTexture(GL_TEXTURE_2D, tex)
    pixels.withUnsafeBytes { raw in
      glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGBA8,
        GLsizei(width),
        GLsizei(height),
        0,
        GL_RGBA,
        GL_UNSIGNED_BYTE,
        raw.baseAddress
      )
    }
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

    return Image(
      textureID: UInt64(tex),
      naturalSize: Size(Float(width), Float(height)),
      pixelScale: pixelScale,
      pixelBytes: pixels,
      pixelWidth: width,
      pixelHeight: height
    )
  }
}
