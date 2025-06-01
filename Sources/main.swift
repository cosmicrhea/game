import unistd
import GLFW
import SGLOpenGL
import Logging
import LoggingOSLog
LoggingSystem.bootstrap(LoggingOSLog.init)
sleep(1) // ffs, apple…

try! GLFWSession.initialize()
GLFWSession.onReceiveError = { error in print("GLFW error: \(error)") }

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward

let window = try! GLFWWindow(width: 640, height: 480, title: "LearnOpenGL")
window.context.makeCurrent()

let vertexShaderSource = """
  #version 330 core
  layout (location = 0) in vec3 aPos;

  void main() {
    gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
  }
"""

//var vertexShader = GLuint()
let vertexShader = glCreateShader(GL_VERTEX_SHADER)
vertexShaderSource.withCString {
  withUnsafePointer(to: $0) {
    glShaderSource(vertexShader, 1, $0, nil)
  }
}
glCompileShader(vertexShader)

do {
  var success = GLint()
  glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &success)
  if success == GL_FALSE {
    var logLength = GLint()
    glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength)
    var infoLog = [GLchar](repeating: 0, count: Int(logLength))
    glGetShaderInfoLog(vertexShader, logLength, nil, &infoLog)
    logger.error(infoLog)
  }
}

let fragmentShaderSource = """
  #version 330 core
  out vec4 FragColor;

  void main() {
    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
  }
"""

let fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
fragmentShaderSource.withCString {
  withUnsafePointer(to: $0) {
    glShaderSource(fragmentShader, 1, $0, nil)
  }
}
glCompileShader(fragmentShader)

do {
  var success = GLint()
  glGetShaderiv(fragmentShader, GL_COMPILE_STATUS, &success)
  if success == GL_FALSE {
    var logLength = GLint()
    glGetShaderiv(fragmentShader, GL_INFO_LOG_LENGTH, &logLength)
    var infoLog = [GLchar](repeating: 0, count: Int(logLength))
    glGetShaderInfoLog(fragmentShader, logLength, nil, &infoLog)
    logger.error(infoLog)
  }
}

let shaderProgram = glCreateProgram()
glAttachShader(shaderProgram, vertexShader)
glAttachShader(shaderProgram, fragmentShader)
glLinkProgram(shaderProgram)

do {
  var success = GLint()
  glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success)
  if success == GL_FALSE {
    var logLength = GLint()
    glGetProgramiv(shaderProgram, GL_INFO_LOG_LENGTH, &logLength)
    var infoLog = [GLchar](repeating: 0, count: Int(logLength))
    glGetProgramInfoLog(shaderProgram, logLength, nil, &infoLog)
    logger.error(infoLog)
  }
}

glDeleteShader(vertexShader)
glDeleteShader(fragmentShader)

let vertices: [Float] = [
  -0.5, -0.5, 0.0,
   0.5, -0.5, 0.0,
   0.0,  0.5, 0.0
];

var vertexBuffer = GLuint()
glGenBuffers(1, &vertexBuffer)

var vertexArray = GLuint()
glGenVertexArrays(1, &vertexArray)

glBindVertexArray(vertexArray)
glBindBuffer(GL_ARRAY_BUFFER, vertexArray)
glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)
glEnableVertexAttribArray(0)

glPolygonMode(GL_FRONT_AND_BACK, GL_FILL)

while !window.shouldClose {
  glClear(GL_COLOR_BUFFER_BIT)
//  glClearColor(0.2, 0.1, 0.1, 1)

  glUseProgram(shaderProgram)
  glBindVertexArray(vertexArray)
  glDrawArrays(GL_TRIANGLES, 0, 3)

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
