/// Errors that can occur during shader operations
enum GLProgramError: Error {
  case fileReadFailed(String, String)
  case compilationFailed(String, String)
  case linkingFailed(String)
  case shaderNotFound(String, String)
  case unknownShaderType(String)
}

/// A shader program that loads, compiles, and links OpenGL shaders
public struct GLProgram {
  let programID: GLuint

  /// Initialize shader program from shader base name
  /// Looks for vertex shader as "name.vert" and fragment shader as "name.frag"
  public init(_ name: String) throws {
    try self.init(name, name)
  }

  /// Initialize shader program from separate vertex and fragment base names
  /// Looks for vertex shader as "vertexName.vert" and fragment shader as "fragmentName.frag"
  public init(_ vertexName: String, _ fragmentName: String) throws {
    programID = glCreateProgram()

    do {
      // Resolve shader names to file paths and load source code
      let vertexPath = try resolveShaderPath(name: vertexName, type: "vertex")
      let fragmentPath = try resolveShaderPath(name: fragmentName, type: "fragment")

      let vertexSource = try loadShaderSource(from: vertexPath)
      let rawFragmentSource = try loadShaderSource(from: fragmentPath)
      let fragmentSource = wrapShaderToyIfNeeded(rawFragmentSource)

      //      print("# \(fragmentName).frag")
      //      print(fragmentSource)

      // Compile shaders
      let vertexShader = try compileShader(source: vertexSource, type: GL_VERTEX_SHADER)
      let fragmentShader = try compileShader(source: fragmentSource, type: GL_FRAGMENT_SHADER)

      // Link program
      glAttachShader(programID, vertexShader)
      glAttachShader(programID, fragmentShader)
      glLinkProgram(programID)

      // Check for linking errors
      try checkLinkingErrors()

      // Clean up shaders (they're linked into the program now)
      glDeleteShader(vertexShader)
      glDeleteShader(fragmentShader)

    } catch let error as GLProgramError {
      // Clean up on error
      if programID != 0 {
        glDeleteProgram(programID)
      }
      throw error
    } catch {
      // Clean up on unexpected error
      if programID != 0 {
        glDeleteProgram(programID)
      }
      throw error
    }
  }

  /// If the fragment source looks like a ShaderToy shader (defines mainImage but no main),
  /// wrap it with uniforms and a main() entry point compatible with GLSL 330 core.
  private func wrapShaderToyIfNeeded(_ source: String) -> String {
    let hasMainImage = source.contains("mainImage(")
    let hasMain = source.contains("void main(")
    guard hasMainImage && !hasMain else { return source }

    let hasVersion = source.contains("#version")
    let versionLine = hasVersion ? "" : "#version 330 core\n"

    let prelude = """
      \(versionLine)out vec4 FragColor;
      uniform vec3 iResolution;
      uniform float iTime;
      uniform float iTimeDelta;
      uniform int iFrame;
      uniform vec4 iMouse;
      uniform vec4 iDate;
      uniform float iSampleRate;
      uniform float iChannelTime[4];
      uniform vec3 iChannelResolution[4];
      uniform sampler2D iChannel0;
      uniform sampler2D iChannel1;
      uniform sampler2D iChannel2;
      uniform sampler2D iChannel3;
      """

    let mainBody = """
      void main() {
        vec4 color = vec4(0.0);
        mainImage(color, gl_FragCoord.xy);
        FragColor = color;
      }
      """

    return prelude + "\n" + source + "\n" + mainBody
  }

  /// Load shader source code from file
  private func loadShaderSource(from filePath: String) throws -> String {
    do {
      return try String(contentsOfFile: filePath, encoding: .utf8)
    } catch {
      logger.error(
        "ERROR::SHADER::FILE_NOT_SUCCESSFULLY_READ: Failed to read shader file at \(filePath): \(error.localizedDescription)"
      )
      throw GLProgramError.fileReadFailed(filePath, error.localizedDescription)
    }
  }

  /// Compile a shader from source code
  private func compileShader(source: String, type: GLenum) throws -> GLuint {
    let shader = glCreateShader(type)

    // Convert Swift string to C string for OpenGL
    source.withCString { shaderSourcePointer in
      var sourcePointer = shaderSourcePointer
      glShaderSource(shader, 1, &sourcePointer, nil)
    }

    glCompileShader(shader)

    // Check for compilation errors
    try checkCompilationErrors(
      shader: shader, type: type == GL_VERTEX_SHADER ? "VERTEX" : "FRAGMENT")

    return shader
  }

  /// Check for shader compilation errors
  private func checkCompilationErrors(shader: GLuint, type: String) throws {
    var success: GLint = 0
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success)

    if success == GL_FALSE {
      var infoLogLength: GLint = 0
      glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLogLength)

      let infoLog = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(infoLogLength))
      defer { infoLog.deallocate() }

      glGetShaderInfoLog(shader, infoLogLength, nil, infoLog)

      let errorMessage = String(cString: infoLog)
      logger.error("ERROR::SHADER_COMPILATION_ERROR of type: \(type)\n\(errorMessage)")
      throw GLProgramError.compilationFailed(type, errorMessage)
    }
  }

  /// Check for program linking errors
  private func checkLinkingErrors() throws {
    var success: GLint = 0
    glGetProgramiv(programID, GL_LINK_STATUS, &success)

    if success == GL_FALSE {
      var infoLogLength: GLint = 0
      glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength)

      let infoLog = UnsafeMutablePointer<GLchar>.allocate(capacity: Int(infoLogLength))
      defer { infoLog.deallocate() }

      glGetProgramInfoLog(programID, infoLogLength, nil, infoLog)

      let errorMessage = String(cString: infoLog)
      logger.error("ERROR::PROGRAM_LINKING_ERROR\n\(errorMessage)")
      throw GLProgramError.linkingFailed(errorMessage)
    }
  }

  /// Use/activate the shader program
  func use() {
    glUseProgram(programID)
  }

  /// Set a boolean uniform value
  func setBool(_ name: String, value: Bool) {
    let location = glGetUniformLocation(programID, name)
    glUniform1i(location, value ? 1 : 0)
  }

  /// Set an integer uniform value
  func setInt(_ name: String, value: Int32) {
    let location = glGetUniformLocation(programID, name)
    glUniform1i(location, value)
  }

  /// Set a float uniform value
  func setFloat(_ name: String, value: Float) {
    let location = glGetUniformLocation(programID, name)
    glUniform1f(location, value)
  }

  /// Set a 3-component vector uniform value
  func setVec2(_ name: String, value: (Float, Float)) {
    let location = glGetUniformLocation(programID, name)
    glUniform2f(location, value.0, value.1)
  }

  /// Set a 3-component vector uniform value
  func setVec3(_ name: String, value: (x: Float, y: Float, z: Float)) {
    let location = glGetUniformLocation(programID, name)
    glUniform3f(location, value.x, value.y, value.z)
  }

  /// Set a 4-component vector uniform value
  func setVec4(_ name: String, value: (Float, Float, Float, Float)) {
    let location = glGetUniformLocation(programID, name)
    glUniform4f(location, value.0, value.1, value.2, value.3)
  }

  /// Set a 4x4 matrix uniform value
  func setMat4(_ name: String, value: UnsafePointer<Float>) {
    let location = glGetUniformLocation(programID, name)
    glUniformMatrix4fv(location, 1, false, value)
  }

  /// Set a 4x4 matrix uniform value from GLMath `mat4`
  func setMat4(_ name: String, value: mat4) {
    let location = glGetUniformLocation(programID, name)
    // Rebind matrix memory to contiguous Float[16] and upload
    withUnsafeBytes(of: value) { rawBuffer in
      let floatPointer = rawBuffer.baseAddress!.assumingMemoryBound(to: Float.self)
      glUniformMatrix4fv(location, 1, false, floatPointer)
    }
  }

  /// Set a Color uniform value (RGB only)
  func setColor(_ name: String, value: Color) {
    let location = glGetUniformLocation(programID, name)
    glUniform3f(location, value.red, value.green, value.blue)
  }

  /// Clean up the shader program
  func delete() {
    glDeleteProgram(programID)
  }

  /// Resolve shader name to file path using Bundle.game
  private func resolveShaderPath(name: String, type: String) throws -> String {
    let fileExtension: String
    switch type {
    case "vertex":
      fileExtension = "vert"
    case "fragment":
      fileExtension = "frag"
    default:
      logger.error("Unknown shader type: \(type)")
      throw GLProgramError.unknownShaderType(type)
    }

    // Look for shader in the module bundle
    guard let shaderPath = Bundle.game.path(forResource: name, ofType: fileExtension) else {
      logger.error(
        "SHADER::FILE_NOT_FOUND: Could not find \(type) shader '\(name).\(fileExtension)' in bundle"
      )
      throw GLProgramError.shaderNotFound(name, fileExtension)
    }

    return shaderPath
  }
}
