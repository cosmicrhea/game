import class AppKit.NSSound
import class Foundation.Bundle

enum UISound {
#if os(macOS)
  static func play(_ name: String) {
    guard let file = Bundle.module.path(forResource: "UI/\(name)", ofType: "wav") else {
      logger.error("failed to load \(name)")
      return
    }

    // todo: cross platform
    NSSound(contentsOfFile: file, byReference: true)?.play()
  }
#else
  static func play(_ name: String) {}
#endif

  static func select() { play("RE_SELECT02") }
  static func shutter() { play("shutter") }
}
