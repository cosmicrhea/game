import Assimp
import Foundation
import GL
import GLMath
import ImageFormats

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
}

class MeshInstance: @unchecked Sendable {

  let scene: Scene
  let mesh: Mesh
  let transformMatrix: mat4

  // Rendering program
  private let program: GLProgram

  var VAO: GLuint = 0
  var VBO: GLuint = 0
  var EBO: GLuint = 0

  // Texture support
  var diffuseTexture: GLuint = 0
  var hasTexture: Bool = false

  // Loading progress callback
  typealias ProgressCallback = (Float) -> Void

  init(scene: Scene, mesh: Mesh, transformMatrix: mat4 = mat4(1)) {
    self.scene = scene
    self.mesh = mesh
    self.transformMatrix = transformMatrix

    // Create shader program
    self.program = try! GLProgram("Common/basic 2")

    glGenVertexArrays(1, &VAO)
    glGenBuffers(1, &VBO)
    glGenBuffers(1, &EBO)

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

    glBindVertexArray(0)

    // Load texture if available
    loadTexture()
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
          let scenePath = Bundle.module.path(forResource: path, ofType: "glb")!
          let scene = try Assimp.Scene(file: scenePath, flags: [.triangulate, .validateDataStructure, .flipUVs]) {
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
          return MeshInstance(scene: scene, mesh: mesh, transformMatrix: transformMatrix)
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

  func draw(projection: mat4, view: mat4, lightDirection: vec3, lightColor: vec3, lightIntensity: Float) {
    program.use()

    // Set matrices
    program.setMat4("projection", value: projection)
    program.setMat4("view", value: view)
    program.setMat4("model", value: transformMatrix)

    // Set lighting uniforms
    program.setVec3("lightDirection", value: (lightDirection.x, lightDirection.y, lightDirection.z))
    program.setVec3("lightColor", value: (lightColor.x, lightColor.y, lightColor.z))
    program.setFloat("lightIntensity", value: lightIntensity)

    // Set texture uniforms
    program.setBool("hasTexture", value: hasTexture)
    if hasTexture {
      program.setInt("diffuseTexture", value: 0)  // Texture unit 0
      glActiveTexture(GL_TEXTURE0)
      glBindTexture(GL_TEXTURE_2D, diffuseTexture)
    }

    glBindVertexArray(VAO)
    glDrawElements(GL_TRIANGLES, GLsizei(mesh.faces.count * 3), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)
  }

  private func loadTexture() {
    // Get material for this mesh
    guard mesh.materialIndex < scene.materials.count else { return }
    let material = scene.materials[mesh.materialIndex]

    // Try to get diffuse texture path
    guard let texturePath = material.getMaterialTexture(texType: .diffuse, texIndex: 0) else { return }

    // Create scene-specific cache key for embedded textures
    let cacheKey = texturePath.hasPrefix("*") ? "\(ObjectIdentifier(scene))_\(texturePath)" : texturePath

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.info("Using cached texture for key \(cacheKey)")
      diffuseTexture = cachedTexture
      hasTexture = true
      return
    }

    logger.info("Loading texture with path \(texturePath)")

    // Check if it's an embedded texture (starts with "*")
    if texturePath.hasPrefix("*") {
      loadEmbeddedTexture(texturePath: texturePath, cacheKey: cacheKey)
    } else {
      loadExternalTexture(texturePath: texturePath)
    }
  }

  private func loadEmbeddedTexture(texturePath: String, cacheKey: String) {
    // Extract texture index from "*0", "*1", etc.
    guard let indexString = texturePath.dropFirst().first,
      let textureIndex = Int(String(indexString)),
      textureIndex < scene.textures.count
    else { return }

    let texture = scene.textures[textureIndex]
    createOpenGLTexture(from: texture, texturePath: texturePath, cacheKey: cacheKey)
  }

  private func loadExternalTexture(texturePath: String) {
    // For now, skip external textures - would need to implement file loading
    // This could be added later with proper file system access
    print("External texture loading not implemented yet: \(texturePath)")
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
    logger.info("Loading texture with path \(texturePath)")

    // Create scene-specific cache key for embedded textures
    let cacheKey = texturePath.hasPrefix("*") ? "\(ObjectIdentifier(scene))_\(texturePath)" : texturePath

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.info("Using cached texture for key \(cacheKey)")
      diffuseTexture = cachedTexture
      hasTexture = true
      onProgress(1.0)
      return
    }

    // Load texture with progress
    await loadEmbeddedTextureAsync(texturePath: texturePath, cacheKey: cacheKey, onProgress: onProgress)
  }

  /// Async version of loadEmbeddedTexture with progress callback
  private func loadEmbeddedTextureAsync(
    texturePath: String, cacheKey: String, onProgress: @escaping @Sendable (Float) -> Void
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
      print("Loading compressed texture: \(texture.achFormatHint), data size: \(data.count)")

      do {
        let image: ImageFormats.Image<ImageFormats.RGBA>

        // Try to determine format from hint
        if texture.achFormatHint.lowercased().contains("png") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: data) { progress in
            Task { @MainActor in
              onProgress(Float(progress))
            }
          }
        } else if texture.achFormatHint.lowercased().contains("webp") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: data)
          onProgress(1.0)
        } else {
          // Try generic loader
          image = try ImageFormats.Image<ImageFormats.RGBA>.load(from: data)
          onProgress(1.0)
        }

        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      } catch {
        print("Failed to decode compressed texture: \(error)")
        glBindTexture(GL_TEXTURE_2D, 0)
        onProgress(1.0)
        return
      }
    } else {
      // Handle uncompressed texture
      let data = texture.textureData
      print("Loading uncompressed texture: \(texture.width)x\(texture.height), data size: \(data.count)")

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
      print("OpenGL texture error: \(error)")
      glBindTexture(GL_TEXTURE_2D, 0)
      onProgress(1.0)
      return
    }

    hasTexture = true
    glBindTexture(GL_TEXTURE_2D, 0)

    // Cache the texture for future use
    TextureCache.shared.cacheTexture(diffuseTexture, for: cacheKey)
    logger.info("Cached texture for key \(cacheKey)")
    onProgress(1.0)
  }

  private func createOpenGLTexture(from texture: Texture, texturePath: String, cacheKey: String) {
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
      print("Loading compressed texture: \(texture.achFormatHint), data size: \(data.count)")

      do {
        let image: ImageFormats.Image<ImageFormats.RGBA>

        // Try to determine format from hint
        if texture.achFormatHint.lowercased().contains("png") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: data) { progress in
            print("Loading PNG texture: \(progress * 100)%")
          }
        } else if texture.achFormatHint.lowercased().contains("webp") {
          image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: data)
        } else {
          // Try generic loader
          image = try ImageFormats.Image<ImageFormats.RGBA>.load(from: data)
        }

        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      } catch {
        print("Failed to decode compressed texture: \(error)")
        glBindTexture(GL_TEXTURE_2D, 0)
        return
      }
    } else {
      // Handle uncompressed texture
      let data = texture.textureData
      print("Loading uncompressed texture: \(texture.width)x\(texture.height), data size: \(data.count)")

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
      print("OpenGL texture error: \(error)")
      glBindTexture(GL_TEXTURE_2D, 0)
      return
    }

    hasTexture = true
    glBindTexture(GL_TEXTURE_2D, 0)

    // Cache the texture for future use
    TextureCache.shared.cacheTexture(diffuseTexture, for: cacheKey)
    logger.info("Cached texture for key \(cacheKey)")
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

    var result: [MeshVertex] = []
    result.reserveCapacity(numberOfVertices)

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
      result.append(MeshVertex(position: p, normal: n, uv: t))
    }
    return result
  }

  func makeIndices32() -> [UInt32] {
    faces.flatMap { face in face.indices.map { UInt32($0) } }
  }
}
