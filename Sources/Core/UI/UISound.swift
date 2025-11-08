//@preconcurrency import Miniaudio

#if os(macOS)
  import class AppKit.NSSound
#endif

//private let engine = try! AudioEngine()

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
  static func navigate() { play("Minimalist10", volume: 0.8) }
  // static func navigate() { play("UR/scroll") }

  static func pageTurn() { play(["page_1", "page_2", "page_3"]) }
}

@MainActor enum UISound {
  static var volume: Float = Config.current.uiVolume

  //  private nonisolated(unsafe) static var sounds: [String: Sound] = [:]
  private nonisolated(unsafe) static var lastPlayedSounds: [String: String] = [:]

  static func play(_ soundName: String, volume: Float = 1) {
    guard let path = Bundle.game.path(forResource: "UI/Sounds/\(soundName)", ofType: "wav") else {
      logger.error("failed to load \(soundName)")
      return
    }

    let sound = NSSound(contentsOfFile: path, byReference: true)!
    sound.volume = volume * Self.volume
    sound.play()

    //    var sound = sounds[soundName]
    //    if sound == nil {
    //      sound = try! Sound(contentsOfFile: file, spatial: false)
    //      sounds[soundName] = sound
    //    }

    //    do {
    //      let sound = try Sound.play(path, spatial: false)
    //      sound.volume = volume
    //    } catch {
    //      logger.error("failed to play \(soundName): \(error)")
    //    }

    //    let sound =
    //    engine.playSound(contentsOfFile: path, spatial: false)
    //    sound.volume = volume * Self.volume

    // guard let sound else { return }
    //    let sound = try! Sound.play(path, spatial: false)
    //    sound.volume = volume * Self.volume
    //    let sound = try! Sound(contentsOfFile: file, spatial: false)
    //    sound.play()
  }

  static func play(_ soundNames: [String]) {
    let key = soundNames.sorted().joined(separator: ",")
    let availableSounds = soundNames.filter { $0 != lastPlayedSounds[key] }
    let selectedSound = availableSounds.randomElement() ?? soundNames.randomElement()!
    lastPlayedSounds[key] = selectedSound
    play(selectedSound)
  }
}
