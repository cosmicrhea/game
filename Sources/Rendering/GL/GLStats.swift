/// Simple global GL statistics for debugging.
enum GLStats {
  nonisolated(unsafe) private static var _textureCount: Int = 0
  nonisolated(unsafe) private static var _bufferCount: Int = 0
  private static let lock = NSLock()

  static func incrementTextures(_ delta: Int = 1) {
    lock.lock()
    _textureCount += delta
    lock.unlock()
  }

  static func decrementTextures(_ delta: Int = 1) {
    lock.lock()
    _textureCount -= delta
    lock.unlock()
  }

  nonisolated(unsafe) static var textureCount: Int {
    lock.lock()
    let v = _textureCount
    lock.unlock()
    return v
  }

  static func incrementBuffers(_ delta: Int = 1) {
    lock.lock()
    _bufferCount += delta
    lock.unlock()
  }

  static func decrementBuffers(_ delta: Int = 1) {
    lock.lock()
    _bufferCount -= delta
    lock.unlock()
  }

  nonisolated(unsafe) static var bufferCount: Int {
    lock.lock()
    let v = _bufferCount
    lock.unlock()
    return v
  }
}
