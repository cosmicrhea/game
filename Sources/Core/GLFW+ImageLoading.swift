import class Foundation.Bundle
import struct Foundation.Data
import class Foundation.FileManager
import struct Foundation.URL
import struct GLFW.Color
import struct GLFW.Image
import struct ImageFormats.Image
import struct ImageFormats.RGBA

extension GLFW.Image {
  init(_ path: String) {
    // Try to locate the resource inside the SPM bundle
    let fileManager = FileManager.default
    let resourceURL = Bundle.module.resourceURL

    var fileURL: URL? = nil
    if let baseURL = resourceURL {
      let directURL = baseURL.appendingPathComponent(path)
      if fileManager.fileExists(atPath: directURL.path) {
        fileURL = directURL
      }
    }

    if let url = fileURL, let data = try? Data(contentsOf: url) {
      let ext = url.pathExtension.lowercased()
      let rawBytes = Array(data)
      let loaded: ImageFormats.Image<ImageFormats.RGBA>?
      if ext == "png" {
        loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: rawBytes)
      } else if ext == "webp" {
        loaded = try? ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: rawBytes)
      } else {
        loaded = try? ImageFormats.Image<ImageFormats.RGBA>.load(from: rawBytes)
      }

      if let image = loaded {
        let b = image.bytes
        var colors: [GLFW.Color] = []
        colors.reserveCapacity(image.width * image.height)
        var i = 0
        while i + 3 < b.count {
          colors.append(GLFW.Color(rBits: b[i], g: b[i + 1], b: b[i + 2], a: b[i + 3]))
          i += 4
        }
        self.init(width: image.width, height: image.height, pixels: colors)
        return
      }
    }

    // Fallback (empty image) if loading fails
    self.init(width: 80, height: 80, pixels: [])
  }
}
