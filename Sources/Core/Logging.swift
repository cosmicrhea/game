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

  private func formatElapsedTime(_ seconds: Double) -> String {
    if seconds < 1.0 {
      let milliseconds = Int(seconds * 1000)
      return "[\(milliseconds) ms]"
    } else {
      return String(format: "[%.2f s]", seconds)
    }
  }
}
