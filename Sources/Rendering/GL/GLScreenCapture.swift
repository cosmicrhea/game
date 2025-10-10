import GL

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.DateFormatter
import struct Foundation.Locale
import struct Foundation.URL
import struct ImageFormats.Image
import struct ImageFormats.RGBA

/// Saves a screenshot of the current OpenGL context to a file.
/// - Parameters:
///   - width: The width of the screenshot in pixels.
///   - height: The height of the screenshot in pixels.
///   - path: The path to save the screenshot to. If `nil`, the screenshot will be saved to the default location.
func saveScreenshot(width: Int32, height: Int32, path: String? = nil) {
  let numPixels = Int(width * height)
  let bytesPerPixel = 4
  var pixelBytes = [UInt8](repeating: 0, count: numPixels * bytesPerPixel)

  glPixelStorei(GL_PACK_ALIGNMENT, 1)
  glReadBuffer(GL_BACK)
  pixelBytes.withUnsafeMutableBytes { rawBuffer in
    if let base = rawBuffer.baseAddress {
      glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, base)
    }
  }

  // Flip rows to convert from OpenGL's bottom-left origin to top-left
  let rowStride = Int(width) * bytesPerPixel
  var flipped = [UInt8](repeating: 0, count: pixelBytes.count)
  for row in 0..<Int(height) {
    let srcStart = row * rowStride
    let dstStart = (Int(height) - 1 - row) * rowStride
    flipped[dstStart..<(dstStart + rowStride)] = pixelBytes[srcStart..<(srcStart + rowStride)]
  }

  do {
    let image = ImageFormats.Image<RGBA>(width: Int(width), height: Int(height), bytes: flipped)
    let pngBytes = try image.encodeToPNG()

    let filePath: String
    if let providedPath = path {
      filePath = providedPath
    } else {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
      var timestamp = formatter.string(from: Date())
      // Insert narrow no-break space before AM/PM for macOS-style naming
      timestamp = timestamp.replacingOccurrences(of: " AM", with: "\u{202F}AM")
        .replacingOccurrences(of: " PM", with: "\u{202F}PM")

      filePath = "/Users/FA/Pictures/Screenshots/Glass Screenshot \(timestamp).png"
    }

    try Data(pngBytes).write(to: URL(fileURLWithPath: filePath))
    logger.info("Saved screenshot to \(filePath)")
  } catch {
    logger.error("Failed to save screenshot: \(String(describing: error))")
  }
}
