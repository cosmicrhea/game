import Foundation
import GL
import GLFW
import ImageFormats

// Usage:
// let effect = ScreenEffect()
// effect.draw(texture: someTexture)

class ScreenEffect {
  @MainActor static var mousePosition: (Float, Float) = (0, 0)
  private var vao: GLuint = 0
  private var vbo: GLuint = 0
  private let shader: GLProgram
  private var captureTexture: GLuint = 0
  private var captureWidth: GLsizei = 0
  private var captureHeight: GLsizei = 0
  private var frameCount: Int32 = 0
  private var lastTime: Double = GLFWSession.currentTime
  private var channelTimes: [Float] = [0, 0, 0, 0]
  private var sampleRate: Float = 44100.0

  init(_ fragmentShaderName: String) {
    // Pass shader base names (no extensions). Vertex shader is a standard fullscreen quad.
    shader = try! GLProgram("common/fullscreen_quad", fragmentShaderName)

    let quadVertices: [Float] = [
      // positions   // texCoords
      -1.0, 1.0, 0.0, 1.0,
      -1.0, -1.0, 0.0, 0.0,
      1.0, -1.0, 1.0, 0.0,

      -1.0, 1.0, 0.0, 1.0,
      1.0, -1.0, 1.0, 0.0,
      1.0, 1.0, 1.0, 1.0,
    ]

    glGenVertexArrays(1, &vao)
    glGenBuffers(1, &vbo)

    glBindVertexArray(vao)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferData(
      GL_ARRAY_BUFFER, quadVertices.count * MemoryLayout<Float>.stride, quadVertices, GL_STATIC_DRAW
    )

    glVertexAttribPointer(
      0, 2, GL_FLOAT, GLboolean(GL_FALSE), GLsizei(4 * MemoryLayout<Float>.stride), nil)
    glEnableVertexAttribArray(0)

    let texOffset = UnsafeRawPointer(bitPattern: 2 * MemoryLayout<Float>.stride)
    glVertexAttribPointer(
      1, 2, GL_FLOAT, GLboolean(GL_FALSE), GLsizei(4 * MemoryLayout<Float>.stride), texOffset)
    glEnableVertexAttribArray(1)

    glBindVertexArray(0)
  }

  func draw(texture: GLuint) {
    glDisable(GL_DEPTH_TEST)
    shader.use()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texture)
    shader.setInt("uTexture", value: 0)
    glBindVertexArray(vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(0)
  }

  /// Draw with explicit window size. Sets `uTexture` (sampler2D) to 0 and, if present,
  /// sets `uResolution` to (width, height) in pixels.
  func draw(texture: GLuint, windowSize: (Int32, Int32)) {
    glDisable(GL_DEPTH_TEST)
    shader.use()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, texture)
    shader.setInt("uTexture", value: 0)

    let resLocation = glGetUniformLocation(shader.programID, "uResolution")
    if resLocation != -1 {
      glUniform2f(resLocation, Float(windowSize.0), Float(windowSize.1))
    }

    glBindVertexArray(vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(0)
  }

  /// Convenience: capture the current back buffer and apply the effect.
  /// Automatically sets `uTexture` and `uResolution` if present.
  @MainActor func draw() {
    draw([:])
  }

  /// Convenience with additional float uniforms, e.g. draw(["amount": 0.8]).
  @MainActor func draw(_ uniforms: [String: Float]) {
    // Query current viewport as our capture size
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
    let width = GLsizei(viewport[2])
    let height = GLsizei(viewport[3])

    // Ensure capture texture exists and matches size
    if captureTexture == 0 {
      glGenTextures(1, &captureTexture)
      glBindTexture(GL_TEXTURE_2D, captureTexture)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
      glBindTexture(GL_TEXTURE_2D, 0)
    }

    if width != captureWidth || height != captureHeight {
      glBindTexture(GL_TEXTURE_2D, captureTexture)
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
      glBindTexture(GL_TEXTURE_2D, 0)
      captureWidth = width
      captureHeight = height
    }

    // Copy from back buffer into the capture texture
    glReadBuffer(GL_BACK)
    glBindTexture(GL_TEXTURE_2D, captureTexture)
    glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, width, height)
    glBindTexture(GL_TEXTURE_2D, 0)

    // Bind and draw with uniforms
    glDisable(GL_DEPTH_TEST)
    shader.use()
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, captureTexture)
    shader.setInt("uTexture", value: 0)

    // Optional resolution uniform (uResolution)
    let resLocation = glGetUniformLocation(shader.programID, "uResolution")
    if resLocation != -1 {
      glUniform2f(resLocation, Float(width), Float(height))
    }

    // ShaderToy uniforms if present
    let iResolutionLoc = glGetUniformLocation(shader.programID, "iResolution")
    if iResolutionLoc != -1 { glUniform3f(iResolutionLoc, Float(width), Float(height), 1.0) }

    let now = GLFWSession.currentTime
    let delta = max(0.0, now - lastTime)
    lastTime = now

    let iTimeLoc = glGetUniformLocation(shader.programID, "iTime")
    if iTimeLoc != -1 { glUniform1f(iTimeLoc, Float(now)) }

    let iTimeDeltaLoc = glGetUniformLocation(shader.programID, "iTimeDelta")
    if iTimeDeltaLoc != -1 { glUniform1f(iTimeDeltaLoc, Float(delta)) }

    let iFrameLoc = glGetUniformLocation(shader.programID, "iFrame")
    if iFrameLoc != -1 { glUniform1i(iFrameLoc, frameCount) }
    frameCount &+= 1

    let iMouseLoc = glGetUniformLocation(shader.programID, "iMouse")
    if iMouseLoc != -1 {
      let mouse = ScreenEffect.mousePosition
      // Convert to bottom-left origin to match gl_FragCoord
      let mouseYGL = Float(height) - mouse.1
      print(mouse, mouseYGL)
      glUniform4f(iMouseLoc, mouse.0, mouseYGL, 0, 0)
    }

    //    // iDate: (year, month, day, seconds)
    //    let iDateLoc = glGetUniformLocation(shader.programID, "iDate")
    //    if iDateLoc != -1 {
    //      let nowDate = Date()
    //      let calendar = Calendar(identifier: .gregorian)
    //      let comps = calendar.dateComponents(
    //        [.year, .month, .day, .hour, .minute, .second], from: nowDate)
    //      let seconds = Float((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0))
    //      glUniform4f(
    //        iDateLoc, Float(comps.year ?? 1970), Float(comps.month ?? 1), Float(comps.day ?? 1), seconds
    //      )
    //    }

    // iSampleRate
    let iSampleRateLoc = glGetUniformLocation(shader.programID, "iSampleRate")
    if iSampleRateLoc != -1 { glUniform1f(iSampleRateLoc, sampleRate) }

    let iChannel0Loc = glGetUniformLocation(shader.programID, "iChannel0")
    if iChannel0Loc != -1 { glUniform1i(iChannel0Loc, 0) }

    // iChannelResolution for bound channels (0 only for now)
    let iChannelResolutionLoc = glGetUniformLocation(shader.programID, "iChannelResolution")
    if iChannelResolutionLoc != -1 {
      // It's an array of 4 vec3s; set index 0, zero the rest
      glUniform3f(iChannelResolutionLoc + 0, Float(width), Float(height), 1.0)
      glUniform3f(iChannelResolutionLoc + 1, 0, 0, 0)
      glUniform3f(iChannelResolutionLoc + 2, 0, 0, 0)
      glUniform3f(iChannelResolutionLoc + 3, 0, 0, 0)
    }

    // iChannelTime array (seconds). For now, set channel0 to iTime, others 0.
    let iChannelTimeLoc = glGetUniformLocation(shader.programID, "iChannelTime")
    if iChannelTimeLoc != -1 {
      glUniform1f(iChannelTimeLoc + 0, Float(now))
      glUniform1f(iChannelTimeLoc + 1, 0)
      glUniform1f(iChannelTimeLoc + 2, 0)
      glUniform1f(iChannelTimeLoc + 3, 0)
    }

    // Additional float uniforms
    for (name, value) in uniforms {
      shader.setFloat(name, value: value)
    }

    glBindVertexArray(vao)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    glBindVertexArray(0)
  }
}
