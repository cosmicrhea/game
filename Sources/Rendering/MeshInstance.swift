import Assimp
import ImageFormats

// Flag to disable HDRI loading for now
private let enableHDRI = false

/// Global texture cache to avoid loading duplicate textures
final class TextureCache: @unchecked Sendable {
  static let shared = TextureCache()

  private var cache: [String: GLuint] = [:]
  private let lock = NSLock()

  private init() {}

  /// Get a cached texture by path, or nil if not cached
  nonisolated func getCachedTexture(for path: String) -> GLuint? {
    lock.lock()
    defer { lock.unlock() }
    return cache[path]
  }

  /// Store a texture in the cache
  nonisolated func cacheTexture(_ texture: GLuint, for path: String) {
    lock.lock()
    defer { lock.unlock() }
    cache[path] = texture
  }

  /// Clear all cached textures (useful for cleanup)
  nonisolated func clearCache() {
    lock.lock()
    defer { lock.unlock() }
    for (_, texture) in cache {
      var tex = texture
      glDeleteTextures(1, &tex)
    }
    cache.removeAll()
  }

  deinit {
    clearCache()
  }
}

struct MeshVertex {
  var position: (AssimpReal, AssimpReal, AssimpReal)
  var normal: (AssimpReal, AssimpReal, AssimpReal)
  var uv: (AssimpReal, AssimpReal)
  var tangent: (AssimpReal, AssimpReal, AssimpReal)
  var bitangent: (AssimpReal, AssimpReal, AssimpReal)

  // Skeletal animation data
  var boneIndices: (UInt8, UInt8, UInt8, UInt8)  // Up to 4 bone indices per vertex
  var boneWeights: (AssimpReal, AssimpReal, AssimpReal, AssimpReal)  // Corresponding weights
}

class MeshInstance: @unchecked Sendable {

  let scene: Scene
  let mesh: Mesh
  let transformMatrix: mat4
  private let sceneIdentifier: String

  // Rendering program
  private let program: GLProgram

  var VAO: GLuint = 0
  var VBO: GLuint = 0
  var EBO: GLuint = 0

  // Skeletal animation support
  private var boneTransforms: [mat4] = []
  private var boneNames: [String] = []
  private var isSkeletalMesh: Bool = false

  // PBR Texture support
  var diffuseTexture: GLuint = 0
  var normalTexture: GLuint = 0
  var roughnessTexture: GLuint = 0
  var metallicTexture: GLuint = 0
  var aoTexture: GLuint = 0

  var hasDiffuseTexture: Bool = false
  var hasNormalTexture: Bool = false
  var hasRoughnessTexture: Bool = false
  var hasMetallicTexture: Bool = false
  var hasAoTexture: Bool = false

  // HDRI Environment map
  var environmentMap: GLuint = 0
  var hasEnvironmentMap: Bool = false

  // Material properties
  var baseColor: vec3 = vec3(0.8, 0.15, 0.6)
  var metallic: Float = 0.0
  var roughness: Float = 0.5
  var emissive: vec3 = vec3(0.0, 0.0, 0.0)
  var opacity: Float = 1.0

  // Loading progress callback
  typealias ProgressCallback = (Float) -> Void

  init(scene: Scene, mesh: Mesh, transformMatrix: mat4 = mat4(1), sceneIdentifier: String) {
    self.scene = scene
    self.mesh = mesh
    self.transformMatrix = transformMatrix
    self.sceneIdentifier = sceneIdentifier

    // Create shader program - use skeletal shader if mesh has bones
    self.isSkeletalMesh = mesh.numberOfBones > 0
    if isSkeletalMesh {
      self.program = try! GLProgram("Common/skeletal", "Common/basic 2")
      initializeBoneData()
    } else {
      self.program = try! GLProgram("Common/basic 2")
    }

    glGenVertexArrays(1, &VAO)
    GLStats.incrementBuffers()
    glGenBuffers(1, &VBO)
    GLStats.incrementBuffers()
    glGenBuffers(1, &EBO)
    GLStats.incrementBuffers()

    glBindVertexArray(VAO)
    glBindBuffer(GL_ARRAY_BUFFER, VBO)

    // Build interleaved vertex buffer
    let vertices = mesh.makeVertices()

    vertices.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO)

    // build index buffer from faces -> flat [UInt32]
    let indices: [UInt32] = mesh.makeIndices32()

    indices.withUnsafeBytes { bytes in
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    // vertex positions
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(
      0, 3, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.position)!))

    // vertex normals
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 3, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.normal)!))

    // vertex texture coords
    glEnableVertexAttribArray(2)
    glVertexAttribPointer(
      2, 2, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.uv)!))

    // vertex tangents
    glEnableVertexAttribArray(3)
    glVertexAttribPointer(
      3, 3, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.tangent)!))

    // vertex bitangents
    glEnableVertexAttribArray(4)
    glVertexAttribPointer(
      4, 3, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.bitangent)!))

    // bone indices (4 components as unsigned bytes)
    glEnableVertexAttribArray(5)
    glVertexAttribPointer(
      5, 4, GL_UNSIGNED_BYTE, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.boneIndices)!))

    // bone weights (4 components as floats)
    glEnableVertexAttribArray(6)
    glVertexAttribPointer(
      6, 4, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.boneWeights)!))

    glBindVertexArray(0)

    // Load texture if available
    loadTexture()

    // Load HDRI environment map
    loadHDRIEnvironmentMap()
  }

  /// Initialize bone data for skeletal animation
  private func initializeBoneData() {
    boneTransforms = Array(repeating: mat4(1), count: mesh.numberOfBones)
    boneNames = mesh.bones.map { $0.name ?? "Unknown" }
  }

  /// Update bone transforms for skeletal animation
  func updateBoneTransforms(_ transforms: [String: mat4]) {
    guard isSkeletalMesh else { return }

    // Check if we have any animated transforms
    let hasAnimatedTransforms = transforms.values.contains { $0 != mat4(1) }

    if !hasAnimatedTransforms {
      // No animation data, use identity matrices to avoid distortion
      print("No animated transforms found, using identity matrices")
      for index in 0..<boneTransforms.count {
        boneTransforms[index] = mat4(1)
      }
      return
    }

    // Update bone transforms using bone index as key
    for index in 0..<boneTransforms.count {
      if let transform = transforms["\(index)"] {
        boneTransforms[index] = transform
      } else {
        // Fallback to identity if no transform found
        boneTransforms[index] = mat4(1)
      }
    }
  }

  deinit {
    if VAO != 0 {
      glDeleteVertexArrays(1, &VAO)
      GLStats.decrementBuffers()
      VAO = 0
    }
    if VBO != 0 {
      glDeleteBuffers(1, &VBO)
      GLStats.decrementBuffers()
      VBO = 0
    }
    if EBO != 0 {
      glDeleteBuffers(1, &EBO)
      GLStats.decrementBuffers()
      EBO = 0
    }
    // Do NOT delete cached 2D textures; cache owns them. But delete environmentMap created per instance.
    if environmentMap != 0 {
      var t = environmentMap
      glDeleteTextures(1, &t)
      environmentMap = 0
    }
  }

  /// Async initializer that loads scene and textures with progress callbacks
  static func loadAsync(
    path: String,
    onSceneProgress: @escaping @Sendable (Float) -> Void,
    onTextureProgress: @escaping @Sendable (Int, Int, Float) -> Void
  ) async throws -> [MeshInstance] {

    // Load scene with progress
    let scene = try await withCheckedThrowingContinuation { continuation in
      Task {
        do {
          let scenePath = Bundle.game.path(forResource: path, ofType: "glb")!
          let scene = try Assimp.Scene(
            file: scenePath, flags: [.triangulate, /*.validateDataStructure, */ .flipUVs, .calcTangentSpace]
          ) {
            progress in
            Task { @MainActor in
              onSceneProgress(progress)
            }
            return true
          }
          continuation.resume(returning: scene)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }

    // Add a small delay to make scene loading progress visible
    // try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

    // Create mesh instances on main thread (OpenGL operations must be on main thread)
    let meshInstances = await MainActor.run {
      scene.meshes
        .filter { $0.numberOfVertices > 0 }
        .map { mesh in
          let transformMatrix = scene.getTransformMatrix(for: mesh)
          return MeshInstance(
            scene: scene, mesh: mesh, transformMatrix: transformMatrix, sceneIdentifier: scene.filePath)
        }
    }

    // Load textures with progress on main thread
    let totalTextures = meshInstances.count
    for (index, meshInstance) in meshInstances.enumerated() {
      // Simulate texture loading progress
      onTextureProgress(index + 1, totalTextures, 0.0)

      // Small delay to make progress visible
      // try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds

      await MainActor.run {
        meshInstance.loadTexture()
        onTextureProgress(index + 1, totalTextures, 1.0)
      }
    }

    return meshInstances
  }

  func draw(
    projection: mat4, view: mat4, cameraPosition: vec3, lightDirection: vec3, lightColor: vec3, lightIntensity: Float,
    fillLightDirection: vec3, fillLightColor: vec3, fillLightIntensity: Float
  ) {
    draw(
      projection: projection, view: view, modelMatrix: transformMatrix, cameraPosition: cameraPosition,
      lightDirection: lightDirection, lightColor: lightColor, lightIntensity: lightIntensity,
      fillLightDirection: fillLightDirection, fillLightColor: fillLightColor, fillLightIntensity: fillLightIntensity)
  }

  func draw(
    projection: mat4, view: mat4, modelMatrix: mat4, cameraPosition: vec3, lightDirection: vec3, lightColor: vec3,
    lightIntensity: Float, fillLightDirection: vec3, fillLightColor: vec3, fillLightIntensity: Float,
    diffuseOnly: Bool = false
  ) {
    program.use()

    // Set matrices
    program.setMat4("projection", value: projection)
    program.setMat4("view", value: view)
    program.setMat4("model", value: modelMatrix)

    // Set bone transforms for skeletal animation
    if isSkeletalMesh {
      program.setInt("numBones", value: Int32(boneTransforms.count))
      for (index, transform) in boneTransforms.enumerated() {
        program.setMat4("boneTransforms[\(index)]", value: transform)
      }

      // Debug: Print bone transform info
      print("Skeletal mesh: \(boneTransforms.count) bone transforms")
      for (index, transform) in boneTransforms.enumerated() {
        print("Bone \(index): \(transform)")
      }
    }

    // Set camera position
    program.setVec3("cameraPosition", value: (cameraPosition.x, cameraPosition.y, cameraPosition.z))

    // Set lighting uniforms
    program.setVec3("lightDirection", value: (lightDirection.x, lightDirection.y, lightDirection.z))
    program.setVec3("lightColor", value: (lightColor.x, lightColor.y, lightColor.z))
    program.setFloat("lightIntensity", value: lightIntensity)
    program.setVec3("fillLightDirection", value: (fillLightDirection.x, fillLightDirection.y, fillLightDirection.z))
    program.setVec3("fillLightColor", value: (fillLightColor.x, fillLightColor.y, fillLightColor.z))
    program.setFloat("fillLightIntensity", value: fillLightIntensity)

    // Set PBR texture uniforms
    program.setBool("hasDiffuseTexture", value: hasDiffuseTexture)
    program.setBool("hasNormalTexture", value: hasNormalTexture)
    program.setBool("hasRoughnessTexture", value: hasRoughnessTexture)
    program.setBool("hasMetallicTexture", value: hasMetallicTexture)
    program.setBool("hasAoTexture", value: hasAoTexture)

    // Set HDRI environment map uniforms
    program.setBool("hasEnvironmentMap", value: hasEnvironmentMap)

    // Set debug uniforms
    program.setBool("diffuseOnly", value: diffuseOnly)

    // Set material properties
    program.setVec3("baseColor", value: (baseColor.x, baseColor.y, baseColor.z))
    program.setFloat("metallic", value: metallic)
    program.setFloat("roughness", value: roughness)
    program.setVec3("emissive", value: (emissive.x, emissive.y, emissive.z))
    program.setFloat("opacity", value: opacity)

    // Bind textures to texture units
    if hasDiffuseTexture {
      program.setInt("diffuseTexture", value: 0)
      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, diffuseTexture)
    }
    if hasNormalTexture {
      program.setInt("normalTexture", value: 1)
      glActiveTexture(GL_TEXTURE1)
      glBindTexture(GL_TEXTURE_2D, normalTexture)
    }
    if hasRoughnessTexture {
      program.setInt("roughnessTexture", value: 2)
      glActiveTexture(GL_TEXTURE2)
      glBindTexture(GL_TEXTURE_2D, roughnessTexture)
    }
    if hasMetallicTexture {
      program.setInt("metallicTexture", value: 3)
      glActiveTexture(GL_TEXTURE3)
      glBindTexture(GL_TEXTURE_2D, metallicTexture)
    }
    if hasAoTexture {
      program.setInt("aoTexture", value: 4)
      glActiveTexture(GL_TEXTURE4)
      glBindTexture(GL_TEXTURE_2D, aoTexture)
    }

    // Bind HDRI environment map
    if hasEnvironmentMap {
      program.setInt("environmentMap", value: 5)
      glActiveTexture(GL_TEXTURE5)
      glBindTexture(GL_TEXTURE_CUBE_MAP, environmentMap)
    }

    glBindVertexArray(VAO)
    glDrawElements(GL_TRIANGLES, GLsizei(mesh.faces.count * 3), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)
  }

  private func loadTexture() {
    // Get material for this mesh
    guard mesh.materialIndex < scene.materials.count else { return }
    let material = scene.materials[mesh.materialIndex]

    // Load material properties
    loadMaterialProperties(material: material)

    // Load all PBR texture types
    loadTextureOfType(.diffuse, material: material, textureID: &diffuseTexture, hasTexture: &hasDiffuseTexture)
    loadTextureOfType(.normals, material: material, textureID: &normalTexture, hasTexture: &hasNormalTexture)
    loadTextureOfType(
      .diffuseRoughness, material: material, textureID: &roughnessTexture, hasTexture: &hasRoughnessTexture)
    loadTextureOfType(.metalness, material: material, textureID: &metallicTexture, hasTexture: &hasMetallicTexture)
    loadTextureOfType(.ambientOcclusion, material: material, textureID: &aoTexture, hasTexture: &hasAoTexture)
  }

  private func loadMaterialProperties(material: Material) {
    // Load base color (diffuse color)
    if let color = material.getMaterialColor(.COLOR_DIFFUSE) {
      baseColor = vec3(color.x, color.y, color.z)
    }

    // Load PBR properties if available
    if let metallicFactor = material.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_METALLIC_FACTOR)?.float.first {
      metallic = metallicFactor
    }

    if let roughnessFactor = material.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_ROUGHNESS_FACTOR)?.float.first {
      roughness = roughnessFactor
    }

    // Load emissive color
    if let emissiveColor = material.getMaterialColor(.COLOR_EMISSIVE) {
      emissive = vec3(emissiveColor.x, emissiveColor.y, emissiveColor.z)
    }

    // Load opacity
    if let opacityValue = material.getMaterialProperty(.OPACITY)?.float.first {
      opacity = opacityValue
    }
  }

  private func loadTextureOfType(
    _ texType: Assimp.TextureType, material: Material, textureID: inout GLuint, hasTexture: inout Bool
  ) {
    // Try to get texture path for this type
    guard let texturePath = material.getMaterialTexture(texType: texType, texIndex: 0) else { return }

    // Create stable cache key across loads for embedded textures by using scene file path
    let cacheKey = texturePath.hasPrefix("*") ? "\(sceneIdentifier)#\(texturePath)" : texturePath

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.trace("Using cached \(texType) texture for key \(cacheKey)")
      textureID = cachedTexture
      hasTexture = true
      return
    }

    //logger.info("Loading \(texType) texture with path \(texturePath)")

    // Check if it's an embedded texture (starts with "*")
    if texturePath.hasPrefix("*") {
      loadEmbeddedTexture(texturePath: texturePath, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
    } else {
      loadExternalTexture(texturePath: texturePath)
    }
  }

  private func loadEmbeddedTexture(
    texturePath: String, cacheKey: String, textureID: inout GLuint, hasTexture: inout Bool
  ) {
    // Extract texture index from "*0", "*1", etc.
    guard let indexString = texturePath.dropFirst().first,
      let textureIndex = Int(String(indexString)),
      textureIndex < scene.textures.count
    else { return }

    let texture = scene.textures[textureIndex]
    createOpenGLTexture(
      from: texture, texturePath: texturePath, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
  }

  private func loadExternalTexture(texturePath: String) {
    // For now, skip external textures - would need to implement file loading
    // This could be added later with proper file system access
    logger.warning("External texture loading not implemented yet: \(texturePath)")
  }

  /// Async version of loadTexture with progress callback
  private func loadTextureAsync(onProgress: @escaping @Sendable (Float) -> Void) async {
    // Get material for this mesh
    guard mesh.materialIndex < scene.materials.count else {
      onProgress(1.0)
      return
    }
    let material = scene.materials[mesh.materialIndex]

    // Try to get diffuse texture path
    guard let texturePath = material.getMaterialTexture(texType: .diffuse, texIndex: 0) else {
      onProgress(1.0)
      return
    }
    logger.trace("Loading texture with path \(texturePath)")

    // Stable cache key across reloads
    let cacheKey = texturePath.hasPrefix("*") ? "\(sceneIdentifier)#\(texturePath)" : texturePath

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.trace("Using cached texture for key \(cacheKey)")
      diffuseTexture = cachedTexture
      hasDiffuseTexture = true
      onProgress(1.0)
      return
    }

    // Load texture with progress
    await loadEmbeddedTextureAsync(texturePath: texturePath, cacheKey: cacheKey, onProgress: onProgress)
  }

  /// Async version of loadEmbeddedTexture with progress callback
  private func loadEmbeddedTextureAsync(
    texturePath: String,
    cacheKey: String,
    onProgress: @escaping @Sendable (Float) -> Void
  ) async {
    // Extract texture index from "*0", "*1", etc.
    guard let indexString = texturePath.dropFirst().first,
      let textureIndex = Int(String(indexString)),
      textureIndex < scene.textures.count
    else {
      onProgress(1.0)
      return
    }

    let texture = scene.textures[textureIndex]
    await createOpenGLTextureAsync(from: texture, texturePath: texturePath, cacheKey: cacheKey, onProgress: onProgress)
  }

  /// Async version of createOpenGLTexture with progress callback
  private func createOpenGLTextureAsync(
    from texture: Texture, texturePath: String, cacheKey: String, onProgress: @escaping @Sendable (Float) -> Void
  ) async {
    glGenTextures(1, &diffuseTexture)
    glBindTexture(GL_TEXTURE_2D, diffuseTexture)

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

    if texture.isCompressed {
      // Handle compressed texture using ImageFormats decoders
      let data = texture.textureData
      logger.trace("Loading compressed texture: \(texture.achFormatHint), data size: \(data.count)")

      do {
        var image: ImageFormats.Image<ImageFormats.RGBA>?

        // Try to determine format from hint
        if texture.achFormatHint.lowercased().contains("png") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: data) { progress in
            Task { @MainActor in
              onProgress(Float(progress))
            }
          } warningHandler: { warning in
            logger.warning("\(texturePath) PNG warning: \(warning)")
          }
        } else if texture.achFormatHint.lowercased().contains("webp") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: data)
          onProgress(1.0)
        } else if texture.achFormatHint.lowercased().contains("jpg")
          || texture.achFormatHint.lowercased().contains("jpeg")
        {
          // Decode JPEG as RGB and upload as RGB
          let jpg = try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: data)
          jpg.bytes.withUnsafeBytes { bytes in
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGB,
              GLsizei(jpg.width), GLsizei(jpg.height),
              0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
          onProgress(1.0)
          image = nil
        } else {
          // Try generic loader
          image = try ImageFormats.Image<ImageFormats.RGBA>.load(from: data)
          onProgress(1.0)
        }
        if let image {
          image.bytes.withUnsafeBytes { bytes in
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        }
      } catch {
        logger.error("Failed to decode compressed texture: \(error)")
        glBindTexture(GL_TEXTURE_2D, 0)
        onProgress(1.0)
        return
      }
    } else {
      // Handle uncompressed texture
      let data = texture.textureData
      logger.trace("Loading uncompressed texture: \(texture.width)x\(texture.height), data size: \(data.count)")

      data.withUnsafeBytes { bytes in
        // Assimp provides BGRA format, convert to RGBA for OpenGL
        glTexImage2D(
          GL_TEXTURE_2D, 0, GL_RGBA,
          GLsizei(texture.width), GLsizei(texture.height),
          0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
      }
      onProgress(1.0)
    }

    // Check for OpenGL errors
    let error = glGetError()
    if error != GL_NO_ERROR {
      logger.error("OpenGL texture error while loading \(texturePath): \(error)")
      glBindTexture(GL_TEXTURE_2D, 0)
      onProgress(1.0)
      return
    }

    hasDiffuseTexture = true
    glBindTexture(GL_TEXTURE_2D, 0)

    // Cache the texture for future use
    TextureCache.shared.cacheTexture(diffuseTexture, for: cacheKey)
    logger.trace("Cached texture for key \(cacheKey)")
    onProgress(1.0)
  }

  private func createOpenGLTexture(
    from texture: Texture,
    texturePath: String,
    cacheKey: String,
    textureID: inout GLuint,
    hasTexture: inout Bool
  ) {
    glGenTextures(1, &textureID)
    glBindTexture(GL_TEXTURE_2D, textureID)

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

    if texture.isCompressed {
      // Handle compressed texture using ImageFormats decoders
      let data = texture.textureData
      logger.trace("Loading compressed texture: \(texture.achFormatHint), data size: \(data.count)")

      do {
        // Try to determine format from hint
        if texture.achFormatHint.lowercased().contains("png") {
          let image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: data) { progress in
            //print("Loading PNG texture: \(progress * 100)%")
          }
          image.bytes.withUnsafeBytes { bytes in
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        } else if texture.achFormatHint.lowercased().contains("webp") {
          let image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: data)
          image.bytes.withUnsafeBytes { bytes in
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }

        } else if texture.achFormatHint.lowercased().contains("jpg")
          || texture.achFormatHint.lowercased().contains("jpeg")
        {
          let image = try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: data)
          image.bytes.withUnsafeBytes { bytes in
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGB,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        } else {
          logger.error("Unsupported texture format: \(texture.achFormatHint)")
        }

      } catch {
        logger.error("Failed to decode compressed \(texture.achFormatHint) texture \(texturePath): \(error)")
        glBindTexture(GL_TEXTURE_2D, 0)
        return
      }
    } else {
      // Handle uncompressed texture
      let data = texture.textureData
      logger.trace("Loading uncompressed texture: \(texture.width)x\(texture.height), data size: \(data.count)")

      data.withUnsafeBytes { bytes in
        // Assimp provides BGRA format, convert to RGBA for OpenGL
        glTexImage2D(
          GL_TEXTURE_2D, 0, GL_RGBA,
          GLsizei(texture.width), GLsizei(texture.height),
          0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
      }
    }

    // Check for OpenGL errors
    let error = glGetError()
    if error != GL_NO_ERROR {
      logger.error("OpenGL texture error while loading \(texturePath): \(error)")
      glBindTexture(GL_TEXTURE_2D, 0)
      return
    }

    hasTexture = true
    glBindTexture(GL_TEXTURE_2D, 0)

    // Cache the texture for future use
    TextureCache.shared.cacheTexture(textureID, for: cacheKey)
    logger.trace("Cached texture for key \(cacheKey)")
  }

  /// Load HDRI environment map from EXR file
  func loadHDRIEnvironmentMap() {
    if !enableHDRI {
      // Use fallback procedural environment
      loadProceduralEnvironment()
      return
    }

    glGenTextures(1, &environmentMap)
    glBindTexture(GL_TEXTURE_CUBE_MAP, environmentMap)

    // Load the actual HDRI EXR file
    //    do {
    let hdriImage = Image(exrPath: "Common/hansaplatz_4k.exr")
    logger.trace("Loaded HDRI: \(hdriImage.pixelWidth)x\(hdriImage.pixelHeight)")

    // Convert HDRI to cube map
    // For now, we'll create a simple cube map from the HDRI
    // TODO: Implement proper equirectangular to cube map conversion
    let cubeSize = 512

    // Generate cube map faces from HDRI
    for face in 0..<6 {
      var faceData = [UInt8](repeating: 0, count: cubeSize * cubeSize * 3)

      // Simple sampling from HDRI for each cube face
      for y in 0..<cubeSize {
        for x in 0..<cubeSize {
          let index = (y * cubeSize + x) * 3

          // Sample from HDRI based on cube face direction
          let (u, v) = getCubeMapUV(face: face, x: x, y: y, size: cubeSize)
          let (hdriX, hdriY) = (Int(u * Float(hdriImage.pixelWidth)), Int(v * Float(hdriImage.pixelHeight)))

          if hdriX >= 0 && hdriX < hdriImage.pixelWidth && hdriY >= 0 && hdriY < hdriImage.pixelHeight {
            let hdriIndex = (hdriY * hdriImage.pixelWidth + hdriX) * 4  // RGBA
            if let pixelBytes = hdriImage.pixelBytes, hdriIndex + 2 < pixelBytes.count {
              faceData[index] = pixelBytes[hdriIndex]  // R
              faceData[index + 1] = pixelBytes[hdriIndex + 1]  // G
              faceData[index + 2] = pixelBytes[hdriIndex + 2]  // B
            }
          }
        }
      }

      glTexImage2D(
        GL_TEXTURE_CUBE_MAP_POSITIVE_X + Int32(face),
        0, GL_RGB, GLsizei(cubeSize), GLsizei(cubeSize),
        0, GL_RGB, GL_UNSIGNED_BYTE, faceData
      )
    }
    //    } catch {
    //      logger.error("Failed to load HDRI: \(error)")
    //      // Fallback to procedural environment
    //      loadProceduralEnvironment()
    //      return
    //    }

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

    // Generate mipmaps for roughness-based LOD
    glGenerateMipmap(GL_TEXTURE_CUBE_MAP)

    hasEnvironmentMap = true
    logger.trace("Loaded HDRI environment map from hansaplatz_4k.exr")
  }

  /// Convert cube map coordinates to UV coordinates
  private func getCubeMapUV(face: Int, x: Int, y: Int, size: Int) -> (Float, Float) {
    let u = (Float(x) + 0.5) / Float(size)
    let v = (Float(y) + 0.5) / Float(size)
    return (u, v)
  }

  /// Fallback procedural environment
  private func loadProceduralEnvironment() {
    let size = 512
    var data = [UInt8](repeating: 0, count: size * size * 3)

    // Generate simple sky gradient
    for i in 0..<size {
      for j in 0..<size {
        let index = (i * size + j) * 3
        let y = Float(i) / Float(size)
        data[index] = UInt8(255 * (0.4 + 0.6 * y))  // R
        data[index + 1] = UInt8(255 * (0.6 + 0.4 * y))  // G
        data[index + 2] = UInt8(255 * 1.0)  // B
      }
    }

    // Upload to all 6 faces of cube map
    for face in 0..<6 {
      glTexImage2D(
        GL_TEXTURE_CUBE_MAP_POSITIVE_X + Int32(face),
        0, GL_RGB, GLsizei(size), GLsizei(size),
        0, GL_RGB, GL_UNSIGNED_BYTE, data
      )
    }

    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE)

    hasEnvironmentMap = true
    logger.trace("Loaded procedural environment map")
  }
}

// MARK: - Scene helpers for transform matrices

extension Scene {
  /// Get transform matrix for a mesh by finding it in the node hierarchy
  func getTransformMatrix(for mesh: Mesh) -> mat4 {
    return findMeshTransform(mesh: mesh, node: rootNode, parentTransform: mat4(1))
  }

  private func findMeshTransform(mesh: Mesh, node: Node, parentTransform: mat4) -> mat4 {
    // Get this node's transformation matrix
    let nodeTransform = convertAssimpMatrix(node.transformation)
    let globalTransform = parentTransform * nodeTransform

    // Check if this node contains the mesh
    for i in 0..<node.numberOfMeshes {
      let meshIndex = node.meshes[i]
      if meshes[meshIndex] === mesh {
        return globalTransform
      }
    }

    // Search in child nodes
    for i in 0..<node.numberOfChildren {
      let childNode = node.children[i]
      let result = findMeshTransform(mesh: mesh, node: childNode, parentTransform: globalTransform)
      if result != mat4(1) {
        return result
      }
    }

    return mat4(1)  // Not found
  }

  /// Convert Assimp matrix to GLMath mat4
  private func convertAssimpMatrix(_ matrix: Assimp.Matrix4x4) -> mat4 {
    let row1 = vec4(Float(matrix.a1), Float(matrix.b1), Float(matrix.c1), Float(matrix.d1))
    let row2 = vec4(Float(matrix.a2), Float(matrix.b2), Float(matrix.c2), Float(matrix.d2))
    let row3 = vec4(Float(matrix.a3), Float(matrix.b3), Float(matrix.c3), Float(matrix.d3))
    let row4 = vec4(Float(matrix.a4), Float(matrix.b4), Float(matrix.c4), Float(matrix.d4))
    return mat4(row1, row2, row3, row4)
  }
}

// MARK: - Mesh helpers for packing GPU data

extension Mesh {
  func makeVertices() -> [MeshVertex] {
    let positions = vertices
    let normals = self.normals
    let uvs = texCoordsPacked.0
    let tangents = self.tangents
    let bitangents = self.bitangents

    var result: [MeshVertex] = []
    result.reserveCapacity(numberOfVertices)

    // Create bone weight mapping for efficient lookup (only if mesh has bones)
    let boneWeightMap = numberOfBones > 0 ? createBoneWeightMap() : [:]

    // Debug: Print bone information
    if numberOfBones > 0 {
      print("Mesh has \(numberOfBones) bones, weight map has \(boneWeightMap.count) entries")
      for (index, bone) in bones.enumerated() {
        print("Bone \(index): \(bone.name ?? "Unknown") with \(bone.numberOfWeights) weights")
      }
    }

    for i in 0..<numberOfVertices {
      let p = (
        positions[i * 3 + 0],
        positions[i * 3 + 1],
        positions[i * 3 + 2]
      )
      let n: (AssimpReal, AssimpReal, AssimpReal)
      if normals.count >= (i * 3 + 3) {
        n = (normals[i * 3 + 0], normals[i * 3 + 1], normals[i * 3 + 2])
      } else {
        n = (0, 0, 0)
      }
      let t: (AssimpReal, AssimpReal)
      if let uvs, uvs.count >= (i * 2 + 2) {
        t = (uvs[i * 2 + 0], uvs[i * 2 + 1])
      } else {
        t = (0, 0)
      }
      let tangent: (AssimpReal, AssimpReal, AssimpReal)
      if tangents.count >= (i * 3 + 3) {
        tangent = (tangents[i * 3 + 0], tangents[i * 3 + 1], tangents[i * 3 + 2])
      } else {
        tangent = (0, 0, 0)
      }
      let bitangent: (AssimpReal, AssimpReal, AssimpReal)
      if bitangents.count >= (i * 3 + 3) {
        bitangent = (bitangents[i * 3 + 0], bitangents[i * 3 + 1], bitangents[i * 3 + 2])
      } else {
        bitangent = (0, 0, 0)
      }

      // Get bone data for this vertex
      let (boneIndices, boneWeights) = getBoneData(for: i, boneWeightMap: boneWeightMap)

      result.append(
        MeshVertex(
          position: p,
          normal: n,
          uv: t,
          tangent: tangent,
          bitangent: bitangent,
          boneIndices: boneIndices,
          boneWeights: boneWeights
        ))
    }
    return result
  }

  /// Create a mapping from vertex index to bone weights for efficient lookup
  private func createBoneWeightMap() -> [Int: [(boneIndex: Int, weight: AssimpReal)]] {
    var weightMap: [Int: [(boneIndex: Int, weight: AssimpReal)]] = [:]

    // Initialize with empty arrays for all vertices
    for i in 0..<numberOfVertices {
      weightMap[i] = []
    }

    // Process each bone's weights with error handling
    for (boneIndex, bone) in bones.enumerated() {
      // Check if bone has valid weight data
      guard bone.numberOfWeights > 0 else { continue }

      // Try to access bone weights safely
      let boneWeights = bone.weights

      // Check if we got valid weights
      guard !boneWeights.isEmpty else { continue }

      for weight in boneWeights {
        let vertexIndex = weight.vertexIndex
        if vertexIndex < numberOfVertices {
          weightMap[vertexIndex, default: []].append((boneIndex: boneIndex, weight: weight.weight))
        }
      }
    }

    return weightMap
  }

  /// Get bone indices and weights for a specific vertex
  private func getBoneData(for vertexIndex: Int, boneWeightMap: [Int: [(boneIndex: Int, weight: AssimpReal)]]) -> (
    (UInt8, UInt8, UInt8, UInt8), (AssimpReal, AssimpReal, AssimpReal, AssimpReal)
  ) {
    guard let vertexWeights = boneWeightMap[vertexIndex], !vertexWeights.isEmpty else {
      // No bone weights for this vertex
      return ((0, 0, 0, 0), (0, 0, 0, 0))
    }

    // Sort weights by weight value (descending) and take up to 4
    let sortedWeights = vertexWeights.sorted { $0.weight > $1.weight }.prefix(4)

    var indices: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var weights: (AssimpReal, AssimpReal, AssimpReal, AssimpReal) = (0, 0, 0, 0)

    for (i, weightData) in sortedWeights.enumerated() {
      switch i {
      case 0:
        indices.0 = UInt8(weightData.boneIndex)
        weights.0 = weightData.weight
      case 1:
        indices.1 = UInt8(weightData.boneIndex)
        weights.1 = weightData.weight
      case 2:
        indices.2 = UInt8(weightData.boneIndex)
        weights.2 = weightData.weight
      case 3:
        indices.3 = UInt8(weightData.boneIndex)
        weights.3 = weightData.weight
      default:
        break
      }
    }

    return (indices, weights)
  }

  func makeIndices32() -> [UInt32] {
    faces.flatMap { face in face.indices.map { UInt32($0) } }
  }
}
