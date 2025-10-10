import class AppKit.NSSound
import class Foundation.Bundle

extension UISound {
  static func select() { play("RE_SELECT02") }
  static func shutter() { play("shutter") }

  static func pageTurn() { play(["page_1", "page_2", "page_3"]) }
}

enum UISound {
  #if os(macOS)
    static func play(_ sound: String) {
      guard let file = Bundle.module.path(forResource: "UI/\(sound)", ofType: "wav") else {
        logger.error("failed to load \(sound)")
        return
      }

      // TODO: cross platform
      NSSound(contentsOfFile: file, byReference: true)?.play()
    }
  #else
    static func play(_ sound: String) {}
  #endif

  nonisolated(unsafe) private static var lastPlayedSounds: [String: String] = [:]

  static func play(_ sounds: [String]) {
    let key = sounds.sorted().joined(separator: ",")
    let availableSounds = sounds.filter { $0 != lastPlayedSounds[key] }
    let selectedSound = availableSounds.randomElement() ?? sounds.randomElement()!
    lastPlayedSounds[key] = selectedSound
    play(selectedSound)
  }
}
