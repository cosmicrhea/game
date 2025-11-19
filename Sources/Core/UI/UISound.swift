#if USE_MINIAUDIO
  import Miniaudio
#endif

#if os(macOS) && !USE_MINIAUDIO
  import class AppKit.NSSound
#endif

extension UISound {
  static func select() { play("RE_SELECT02") }
  // static func select() { play("Minimalist10") }
  // static func select() { play("UR/accept") }

  //  static func cancel() { play("UR/cancel") }
  static func cancel() { play("RE_SELECT06") }

  static func error() { play("UR/error") }

  static func shutter() { play("shutter") }
  //static func gong() { play("gong") }
  static func woosh() { play("woosh") }

  // static func navigate() { play("SFX_BlackBoardSinglev9", volume: 0.5) }
  static func combine() { play("Minimalist13", volume: 0.9) }
  static func navigate() { play("Minimalist10", volume: 0.8) }
  static func scroll() { play("UR/scroll", volume: 0.5) }
  // static func navigate() { play("UR/scroll") }

  static func pageTurn() { play(["page_1", "page_2", "page_3"]) }
}

@MainActor enum UISound {
  static var volume: Float = Config.current.uiVolume

  private nonisolated(unsafe) static var lastPlayedSounds: [String: String] = [:]

  static func play(_ soundName: String, volume: Float = 1) {
    guard !Self.volume.isZero else { return }

    guard let path = Bundle.game.path(forResource: "UI/Sounds/\(soundName)", ofType: "wav") else {
      logger.error("cannot find \(soundName)")
      return
    }

    #if USE_MINIAUDIO
      print("using miniaudio")
      // Use miniaudio - Sound class already caches data sources internally
      do {
        let sound = try Sound(contentsOfFile: path, spatial: false)
        sound.volume = volume * Self.volume
        _ = sound.play()
      } catch {
        logger.error("failed to play \(soundName): \(error)")
      }
    #else
      // Use NSSound (macOS) or fallback
      #if os(macOS)
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else {
          logger.error("failed to load \(soundName)")
          return
        }

        sound.volume = volume * Self.volume
        sound.play()
      #else
        logger.warning("UISound not supported on this platform without USE_MINIAUDIO")
      #endif
    #endif
  }

  static func play(_ soundNames: [String]) {
    let key = soundNames.sorted().joined(separator: ",")
    let availableSounds = soundNames.filter { $0 != lastPlayedSounds[key] }
    let selectedSound = availableSounds.randomElement() ?? soundNames.randomElement()!
    lastPlayedSounds[key] = selectedSound
    play(selectedSound)
  }
}
