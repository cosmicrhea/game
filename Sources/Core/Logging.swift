import Logging
import LoggingOSLog
import GL

let logger = Logger(label: "local.Glass")

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
}
