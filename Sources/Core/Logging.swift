import Foundation
import Logging

let logger = {
  var logger = Logger(label: "local.cosmicrhea.Game")
  logger.logLevel = .debug
  return logger
}()

extension Logger {
  func error(_ cString: [GLchar]) {
    error("\(String(cString: cString, encoding: .utf8)!)")
  }

  func glShaderError(_ shader: GLuint) {
    var logLength = GLint()
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength)

    var infoLog = [GLchar](repeating: 0, count: Int(logLength))
    glGetShaderInfoLog(shader, logLength, nil, &infoLog)

    error(infoLog)
  }

  func glProgramError(_ program: GLuint) {
    var logLength = GLint()
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength)

    var infoLog = [GLchar](repeating: 0, count: Int(logLength))
    glGetProgramInfoLog(program, logLength, nil, &infoLog)

    error(infoLog)
  }

  /// Measures execution time and logs it with the specified level (defaults to .info)
  func measure(_ message: String, level: Logger.Level = .info, _ closure: () throws -> Void) rethrows {
    let startTime = ProcessInfo.processInfo.systemUptime
    try closure()
    let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime

    let formattedTime = formatElapsedTime(elapsedTime)
    self.log(level: level, "\(formattedTime) \(message)")
  }

  /// Measures execution time and logs it with the specified level (defaults to .info), returning the closure's result
  func measure<T>(_ message: String, level: Logger.Level = .info, _ closure: () throws -> T) rethrows -> T {
    let startTime = ProcessInfo.processInfo.systemUptime
    let result = try closure()
    let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime

    let formattedTime = formatElapsedTime(elapsedTime)
    self.log(level: level, "\(formattedTime) \(message)")
    return result
  }

  /// Measures execution time and logs it with the specified level (defaults to .info), returning the closure's result
  func measure<T>(_ message: String, level: Logger.Level = .info, _ closure: () async throws -> T) async rethrows -> T {
    let startTime = ProcessInfo.processInfo.systemUptime
    let result = try await closure()
    let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime

    let formattedTime = formatElapsedTime(elapsedTime)
    self.log(level: level, "\(formattedTime) \(message)")
    return result
  }

  /// Measures execution time and logs it with the specified level (defaults to .info), returning the closure's result
  /// MainActor variant for use with MainActor-isolated closures
  @MainActor
  func measureOnMainActor<T>(_ message: String, level: Logger.Level = .info, _ closure: @MainActor () async throws -> T) async rethrows -> T {
    let startTime = ProcessInfo.processInfo.systemUptime
    let result = try await closure()
    let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime

    let formattedTime = formatElapsedTime(elapsedTime)
    self.log(level: level, "\(formattedTime) \(message)")
    return result
  }

  private func formatElapsedTime(_ seconds: Double) -> String {
    if seconds < 1.0 {
      let milliseconds = Int(seconds * 1000)
      return String(format: "[%4d ms]", milliseconds)
    } else {
      return String(format: "[%4.2f s ]", seconds)
    }
  }
}

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct PrettyConsoleLogHandler: LogHandler {
  var logLevel: Logger.Level = .trace
  let label: String
  var metadata = Logger.Metadata()

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private static let lock = NSLock()

  private static let useColor: Bool = {
    let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
    let isTTY = isatty(STDERR_FILENO) != 0
    return isTTY && term != "dumb"
  }()

  private static let levelWidth = 8 // "critical"

  init(label: String) {
    self.label = label
  }

  subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { metadata[metadataKey] }
    set { metadata[metadataKey] = newValue }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let timestamp = Self.dateFormatter.string(from: Date())
    let levelText = Self.paddedLevel(level)
    var formedMessage = "\(timestamp) \(levelText) "

    var messageText = message.description
    if messageText.hasPrefix("⚠️ ") {
      messageText = messageText.replacingOccurrences(
        of: "⚠️ ",
        with: "⚠️  ",
        options: [.anchored]
      )
    }
    if !messageText.isEmpty {
      formedMessage += " \(messageText)"
    }

    if let metadataString = combinedMetadataString(override: metadata) {
      formedMessage += " \(metadataString)"
    }

    Self.writeLine(formedMessage)
  }

  private func combinedMetadataString(override: Logger.Metadata?) -> String? {
    let merged = metadata.merging(override ?? Logger.Metadata()) { _, new in new }
    guard !merged.isEmpty else { return nil }
    return merged.map { "\($0)=\($1)" }.joined(separator: " ")
  }

  private static func paddedLevel(_ level: Logger.Level) -> String {
    let plain = levelString(level).leftPadded(to: levelWidth)
    guard useColor else { return plain }
    return colorCode(level) + plain + colorReset
  }

  private static func levelString(_ level: Logger.Level) -> String {
    switch level {
    case .trace: return "trace"
    case .debug: return "debug"
    case .info: return "info"
    case .notice: return "notice"
    case .warning: return "warning"
    case .error: return "error"
    case .critical: return "critical"
    }
  }

  private static func colorCode(_ level: Logger.Level) -> String {
    switch level {
    case .trace: return "\u{001B}[90m" // bright black
    case .debug: return "\u{001B}[36m" // cyan
    case .info: return "\u{001B}[32m" // green
    case .notice: return "\u{001B}[34m" // blue
    case .warning: return "\u{001B}[33m" // yellow
    case .error: return "\u{001B}[31m" // red
    case .critical: return "\u{001B}[35m" // magenta
    }
  }

  private static let colorReset = "\u{001B}[0m"

  private static func writeLine(_ line: String) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    lock.lock()
    defer { lock.unlock() }
    FileHandle.standardError.write(data)
  }
}

private extension String {
  func leftPadded(to width: Int) -> String {
    let padding = max(0, width - count)
    guard padding > 0 else { return self }
    return String(repeating: " ", count: padding) + self
  }
}
