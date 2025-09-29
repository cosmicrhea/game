import Assimp
import Foundation
import GLFW
import Logging
import LoggingOSLog
import SGLMath
import SGLOpenGL
import unistd

import SwiftCrossUI
import DefaultBackend

struct YourApp: App {
  @State var count = 0

  var body: some SwiftCrossUI.Scene {
    WindowGroup("YourApp") {
      HStack {
        Button("-") { count -= 1 }
        Text("Count: \(count)")
        Button("+") { count += 1 }
      }
      .padding()
    }
  }
}

//YourApp.main()

//import class AppKit.NSScreen

typealias glm = SGLMath

LoggingSystem.bootstrap(LoggingOSLog.init)
sleep(1)  // ffs, apple… https://developer.apple.com/forums/thread/765445

try! GLFWSession.initialize()
GLFWSession.onReceiveError = { error in print("GLFW error: \(error)") }

GLFWWindow.hints.contextVersion = (4, 1)
GLFWWindow.hints.openGLProfile = .core
GLFWWindow.hints.openGLCompatibility = .forward

let window = try! GLFWWindow(width: 1280, height: 720, title: "")
window.nsWindow?.styleMask.insert(.fullSizeContentView)
//window.nsWindow?.setFrameTopLeftPoint(.init(x: 0, y: NSScreen.main!.frame.height))
//window.nsWindow?.titlebarAppearsTransparent = true
window.position = .zero
window.context.makeCurrent()

var polygonMode = GL_FILL

window.keyInputHandler = { _, key, _, state, _ in
  if key == .comma && state == .pressed {
    Sound.play("RE_SELECT02")
    polygonMode = polygonMode == GL_FILL ? GL_LINE : GL_FILL
  }
}

let vertexShaderSource = """
    #version 330 core
    layout (location = 0) in vec3 aPos;
  
    void main() {
      gl_Position = vec4(aPos.x, aPos.y, aPos.z, 1.0);
    }
  """

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
  if success == GL_FALSE { logger.glShaderError(vertexShader) }
}

let fragmentShaderSource = """
    #version 330 core
    out vec4 FragColor;
  
    void main() {
      FragColor = vec4(1.0f, 0.33f, 1.0f, 1.0f);
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
  if success == GL_FALSE { logger.glShaderError(fragmentShader) }
}

let shaderProgram = glCreateProgram()
glAttachShader(shaderProgram, vertexShader)
glAttachShader(shaderProgram, fragmentShader)
glLinkProgram(shaderProgram)

do {
  var success = GLint()
  glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success)
  if success == GL_FALSE { logger.glProgramError(shaderProgram) }
}

glDeleteShader(vertexShader)
glDeleteShader(fragmentShader)

let vertices: [Float] = [
  -0.5, -0.5, 0.0,
   0.5, -0.5, 0.0,
   0.0, 0.5, 0.0,
]

var vertexBuffer = GLuint()
glGenBuffers(1, &vertexBuffer)

var vertexArray = GLuint()
glGenVertexArrays(1, &vertexArray)

glBindVertexArray(vertexArray)
glBindBuffer(GL_ARRAY_BUFFER, vertexArray)
glBufferData(GL_ARRAY_BUFFER, vertices.count * MemoryLayout<Float>.stride, vertices, GL_STATIC_DRAW)
//glVertexAttribPointer(index: 0, size: 3, type: GL_FLOAT, normalized: false, stride: GLsizei(3 * MemoryLayout<Float>.stride), pointer: nil)
glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)
glEnableVertexAttribArray(0)

let scenePath = Bundle.module.path(forResource: "actors/rat", ofType: "glb")!

let scene = try! Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure])
//scene.rootNode.transformation = .init()
print("\(scene.rootNode)")
//print("\(scene.meshes)")
////print("\(scene.meshes.map { $0.vertices })")
////print("\(scene.meshes.map { $0.numFaces })")
//print("\(scene.meshes.map { $0.faces })")
////print("\(scene.meshes.map { $0.numVertices })")
////print("\(scene.meshes.map { $0.numBones })")

let renderers = scene.meshes
  .filter { $0.numberOfVertices > 0 }
  .map { MeshRenderer(scene: scene, mesh: $0) }

while !window.shouldClose {
  glClear(GL_COLOR_BUFFER_BIT)
  //  glClearColor(0.2, 0.1, 0.1, 1)

  //print(GLFWSession.currentTime)

//    var model = mat4(1)
//    model = glm.translate(model, vec3())
//    model = glm.rotate(model, radians(20.0), vec3(1, 0.3, 0.5))

  glPolygonMode(GL_FRONT_AND_BACK, polygonMode)

  glUseProgram(shaderProgram)
//  glBindVertexArray(vertexArray)
//  glDrawArrays(GL_TRIANGLES, 0, 3)

  renderers.forEach { $0.draw() }

  window.swapBuffers()
  GLFWSession.pollInputEvents()
}
