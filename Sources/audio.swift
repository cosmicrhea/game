import class Foundation.Bundle
import class AppKit.NSSound

class Sound {
  static func play(_ name: String) {
    guard let file = Bundle.module.path(forResource: "ui/\(name)", ofType: "WAV") else {
      logger.error("failed to load \(name)")
      return
    }

    NSSound(contentsOfFile: file, byReference: true)?.play()
  }
}
