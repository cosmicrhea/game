import Logging
import OpenGL
import LoggingOSLog

extension Logger {
  func error(_ cString: [GLchar]) { error("\(String(cString: cString, encoding: .utf8)!)") }
}

let logger = Logger(label: "local.LearnOpenGL")
