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

        // Handle SVG files
        if ext == "svg" {
          self = Image(svgData: data, pixelScale: pixelScale, targetSize: size, strokeWidth: strokeWidth)
          return
        }

        // Handle other image formats
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

  /// Creates an Image by rendering to an offscreen framebuffer.
  /// - Parameters:
  ///   - size: The size of the offscreen image
  ///   - pixelScale: Scale factor for the image (default: 1.0)
  ///   - renderBlock: A closure that renders content to the offscreen framebuffer
  @MainActor
  public init(size: Size, pixelScale: Float = 1.0, renderBlock: () -> Void) {
    print("Creating offscreen image with size: \(size)")

    // Create a framebuffer for offscreen rendering
    let framebufferID = Engine.shared.renderer.createFramebuffer(size: size, scale: pixelScale)
    print("Created framebuffer ID: \(framebufferID)")

    // Begin rendering to the framebuffer
    Engine.shared.renderer.beginFramebuffer(framebufferID)

    // Clear the framebuffer
    Engine.shared.renderer.setClearColor(.clear)

    // Create a GraphicsContext for offscreen rendering
    let offscreenContext = GraphicsContext(renderer: Engine.shared.renderer, scale: pixelScale)
    GraphicsContext.withContext(offscreenContext) {
      renderBlock()
    }

    // End framebuffer rendering
    Engine.shared.renderer.endFramebuffer()

    // Create an Image from the framebuffer texture
    guard let textureID = Engine.shared.renderer.getFramebufferTextureID(framebufferID) else {
      print("Failed to get framebuffer texture ID, using fallback")
      // Fallback to a 1x1 white pixel if framebuffer fails
      self = Image.uploadToGL(pixels: [255, 255, 255, 255], width: 1, height: 1, pixelScale: pixelScale)
      return
    }

    print("Got texture ID: \(textureID)")
    self = Image(
      textureID: textureID,
      naturalSize: size,
      pixelScale: pixelScale,
      framebufferID: framebufferID
    )
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
      framebufferID: nil,
      pixelBytes: pixels,
      pixelWidth: width,
      pixelHeight: height
    )
  }
}
