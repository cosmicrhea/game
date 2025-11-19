import Foundation
import Dispatch

/// Errors that can occur during shader operations
enum GLProgramError: Error {
  case fileReadFailed(String, String)
  case compilationFailed(String, String)
  case linkingFailed(String)
  case shaderNotFound(String, String)
  case unknownShaderType(String)
}

/// Internal class to manage file watchers for shader hotloading
private final class GLProgramFileWatcher: @unchecked Sendable {
  private var vertexWatcher: DispatchSourceFileSystemObject?
  private var fragmentWatcher: DispatchSourceFileSystemObject?
  private let vertexPath: String
  private let fragmentPath: String
  private let vertexName: String
  private let fragmentName: String
  private var onFileChanged: (@Sendable () -> Void)?
  private let queue = DispatchQueue(label: "local.cosmicrhea.Game.shaderHotload", qos: .utility)
  nonisolated(unsafe) private var pendingRecompile: Bool = false

  init(
    vertexPath: String, fragmentPath: String, vertexName: String, fragmentName: String,
    onFileChanged: @escaping @Sendable () -> Void
  ) {
    self.vertexPath = vertexPath
    self.fragmentPath = fragmentPath
    self.vertexName = vertexName
    self.fragmentName = fragmentName
    self.onFileChanged = onFileChanged

    setupWatchers()
  }

  func updateCallback(_ callback: @escaping @Sendable () -> Void) {
    onFileChanged = callback
  }

  private func setupWatchers() {
    // Use platform-specific file open flags
    // O_EVTONLY is macOS-specific, use O_RDONLY on Linux
    #if os(macOS)
      let openFlags = O_EVTONLY
    #else
      let openFlags = O_RDONLY
    #endif

    // Watch vertex shader
    let vertexFileDescriptor = open(vertexPath, openFlags)
    if vertexFileDescriptor >= 0 {
      vertexWatcher = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: vertexFileDescriptor,
        eventMask: DispatchSource.FileSystemEvent.write,
        queue: queue
      )
      vertexWatcher?.setEventHandler { @Sendable [weak self] in
        guard let self = self else { return }
        // Debounce: wait a bit for file writes to complete
        let callback = self.onFileChanged
        let currentPending = self.pendingRecompile
        guard !currentPending else { return }
        self.pendingRecompile = true
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(100)) {
          @Sendable in
          callback?()
          // Reset flag after a delay
          DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(500)) {
            @Sendable in
            self.pendingRecompile = false
          }
        }
      }
      vertexWatcher?.resume()
    }

    // Watch fragment shader
    let fragmentFileDescriptor = open(fragmentPath, openFlags)
    if fragmentFileDescriptor >= 0 {
      fragmentWatcher = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fragmentFileDescriptor,
        eventMask: DispatchSource.FileSystemEvent.write,
        queue: queue
      )
      fragmentWatcher?.setEventHandler { @Sendable [weak self] in
        guard let self = self else { return }
        // Debounce: wait a bit for file writes to complete
        let callback = self.onFileChanged
        let currentPending = self.pendingRecompile
        guard !currentPending else { return }
        self.pendingRecompile = true
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(100)) {
          @Sendable in
          callback?()
          // Reset flag after a delay
          DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(500)) {
            @Sendable in
            self.pendingRecompile = false
          }
        }
      }
      fragmentWatcher?.resume()
    }
  }

  deinit {
    vertexWatcher?.cancel()
    fragmentWatcher?.cancel()
  }
}

/// A shader program that loads, compiles, and links OpenGL shaders
public final class GLProgram: @unchecked Sendable {
  private(set) var programID: GLuint
  private let vertexName: String
  private let fragmentName: String
  private let vertexPath: String
  private let fragmentPath: String

  // Static registry to track file watchers for each program
  nonisolated(unsafe) private static var fileWatchers: [GLuint: GLProgramFileWatcher] = [:]
  nonisolated(unsafe) private static var programInstances: [GLuint: Weak<GLProgram>] = [:]
  private static let watcherLock = NSLock()

  // Helper class for weak references
  private class Weak<T: AnyObject> {
    weak var value: T?
    init(_ value: T) {
      self.value = value
    }
  }

  /// Initialize shader program from shader base name
  /// Looks for vertex shader as "name.vert" and fragment shader as "name.frag"
  public convenience init(_ name: String) throws {
    try self.init(name, name)
  }

  /// Initialize shader program from separate vertex and fragment base names
  /// Looks for vertex shader as "vertexName.vert" and fragment shader as "fragmentName.frag"
  public init(_ vertexName: String, _ fragmentName: String) throws {
    // Store names first (before using them)
    self.vertexName = vertexName
    self.fragmentName = fragmentName

    let initialProgramID = glCreateProgram()
    programID = initialProgramID

    // Resolve shader names to file paths
    let resolvedVertexPath = try Self.resolveShaderPath(name: vertexName, type: "vertex")
    let resolvedFragmentPath = try Self.resolveShaderPath(name: fragmentName, type: "fragment")

    // Store paths for hotloading
    self.vertexPath = resolvedVertexPath
    self.fragmentPath = resolvedFragmentPath

    do {
      // Load source code
      let vertexSource = try loadShaderSource(from: resolvedVertexPath)
      let rawFragmentSource = try loadShaderSource(from: resolvedFragmentPath)
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

      // Set up file watching for hotloading
      setupFileWatchers()

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

  /// Set up file watchers for shader hotloading
  private func setupFileWatchers() {
    Self.watcherLock.lock()
    defer { Self.watcherLock.unlock() }

    // Remove any existing watcher for this programID
    Self.fileWatchers[programID] = nil

    // Store weak reference to this instance for automatic recompilation
    Self.programInstances[programID] = Weak(self)

    // Create new watcher with callback that will trigger recompilation
    let watcher = GLProgramFileWatcher(
      vertexPath: vertexPath,
      fragmentPath: fragmentPath,
      vertexName: vertexName,
      fragmentName: fragmentName
    ) { @Sendable [weak self] in
      // This callback will be called when files change
      // Automatically recompile the shader
      guard let self = self else { return }
      do {
        try self.recompile()
      } catch {
        logger.error("❌ Automatic shader recompilation failed: \(error)")
      }
    }

    Self.fileWatchers[programID] = watcher
  }

  /// Manually trigger recompilation of the shader
  public func recompile() throws {
    logger.info("🔄 Recompiling shader program \(programID)")

    // Delete old program
    let oldProgramID = programID
    glDeleteProgram(oldProgramID)

    // Create new program
    programID = glCreateProgram()

    do {
      // Load source code
      let vertexSource = try loadShaderSource(from: vertexPath)
      let rawFragmentSource = try loadShaderSource(from: fragmentPath)
      let fragmentSource = wrapShaderToyIfNeeded(rawFragmentSource)

      // Compile shaders
      let vertexShader = try compileShader(source: vertexSource, type: GL_VERTEX_SHADER)
      let fragmentShader = try compileShader(source: fragmentSource, type: GL_FRAGMENT_SHADER)

      // Link program
      glAttachShader(programID, vertexShader)
      glAttachShader(programID, fragmentShader)
      glLinkProgram(programID)

      // Check for linking errors
      try checkLinkingErrors()

      // Clean up shaders
      glDeleteShader(vertexShader)
      glDeleteShader(fragmentShader)

      // Update file watcher registration
      Self.watcherLock.lock()
      if let watcher = Self.fileWatchers[oldProgramID] {
        Self.fileWatchers.removeValue(forKey: oldProgramID)
        Self.fileWatchers[programID] = watcher
      }
      if let weakRef = Self.programInstances[oldProgramID] {
        Self.programInstances.removeValue(forKey: oldProgramID)
        Self.programInstances[programID] = weakRef
      }
      Self.watcherLock.unlock()

      logger.info("✅ Shader recompiled successfully")
    } catch {
      // Restore old programID on error
      programID = oldProgramID
      logger.error("❌ Shader recompilation failed: \(error)")
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
      uniform vec2 iWindowSize;
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
        // Scale fragCoord from window space to coordinate space (iResolution)
        vec2 scaledFragCoord = gl_FragCoord.xy;
        if (iWindowSize.x > 0.0 && iWindowSize.y > 0.0) {
          scaledFragCoord = gl_FragCoord.xy * iResolution.xy / iWindowSize.xy;
        }
        mainImage(color, scaledFragCoord);
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
    // Remove file watcher and instance reference
    Self.watcherLock.lock()
    Self.fileWatchers.removeValue(forKey: programID)
    Self.programInstances.removeValue(forKey: programID)
    Self.watcherLock.unlock()

    glDeleteProgram(programID)
  }

  deinit {
    // Clean up watchers if delete() wasn't called
    Self.watcherLock.lock()
    Self.fileWatchers.removeValue(forKey: programID)
    Self.programInstances.removeValue(forKey: programID)
    Self.watcherLock.unlock()

    if programID != 0 {
      glDeleteProgram(programID)
    }
  }

  /// Resolve shader name to file path using Bundle.game
  private static func resolveShaderPath(name: String, type: String) throws -> String {
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
