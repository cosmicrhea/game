import ImageFormats
import CGLTF
import GLTF

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
  var position: (Float, Float, Float)
  var normal: (Float, Float, Float)
  var uv: (Float, Float)
  var tangent: (Float, Float, Float)
  var bitangent: (Float, Float, Float)

  // Skeletal animation data
  var boneIndices: (UInt8, UInt8, UInt8, UInt8)  // Up to 4 bone indices per vertex
  var boneWeights: (Float, Float, Float, Float)  // Corresponding weights
}

class MeshInstance: @unchecked Sendable {

  let sceneData: Scene
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

  // Node reference for checking visibility (optional)
  weak var node: Node?

  init(sceneData: Scene, mesh: Mesh, transformMatrix: mat4 = mat4(1), sceneIdentifier: String) {
    self.sceneData = sceneData
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
  
  /// Get material for this mesh
  private var material: Material? {
    guard mesh.materialIndex < sceneData.materials.count else { return nil }
    return sceneData.materials[mesh.materialIndex]
  }

  /// Update bone transforms for skeletal animation
  func updateBoneTransforms(_ transforms: [String: mat4]) {
    guard isSkeletalMesh else { return }

    // Check if we have any animated transforms
    let hasAnimatedTransforms = transforms.values.contains { $0 != mat4(1) }

    if !hasAnimatedTransforms {
      // No animation data, use identity matrices to avoid distortion
      logger.trace("No animated transforms found, using identity matrices")
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

  /// Check if this mesh instance is visible (node is not hidden)
  func isVisible() -> Bool {
    guard let node = node else {
      // If no node reference, assume visible
      return true
    }
    return !node.isHidden
  }

  /// Async initializer that loads scene and textures with progress callbacks (GLTF version)
  static func loadAsync(
    path: String,
    onSceneProgress: @escaping @Sendable (Float) -> Void,
    onTextureProgress: @escaping @Sendable (Int, Int, Float) -> Void
  ) async throws -> [MeshInstance] {

    // Load GLTF document with progress
    let scenePath = Bundle.game.path(forResource: path, ofType: "glb")!
    let url = URL(fileURLWithPath: scenePath)
    
    let gltfDocument = try await GLTFDocument(contentsOf: url) { progress in
      Task { @MainActor in
        onSceneProgress(Float(progress))
      }
    }
    
    // Convert to our Scene
    let sceneData = Scene(gltfDocument, filePath: scenePath)

    // Create mesh instances on main thread (OpenGL operations must be on main thread)
    let meshInstances = await MainActor.run {
      // Build a map from mesh index to node for proper transform lookup
      var meshToNodeMap: [Int: Node] = [:]
      func buildMeshToNodeMap(node: Node) {
        for meshIndex in node.meshes {
          // If multiple nodes reference the same mesh, use the first one found
          if meshToNodeMap[meshIndex] == nil {
            meshToNodeMap[meshIndex] = node
          }
        }
        for child in node.children {
          buildMeshToNodeMap(node: child)
        }
      }
      buildMeshToNodeMap(node: sceneData.rootNode)
      
      // Debug: Print root node structure
      logger.debug("Root node: '\(sceneData.rootNode.name)', children: \(sceneData.rootNode.children.count), meshes: \(sceneData.rootNode.meshes.count)")
      logger.debug("Root node transform translation: (\(sceneData.rootNode.transformation[3].x), \(sceneData.rootNode.transformation[3].y), \(sceneData.rootNode.transformation[3].z))")
      
      // Debug: Print mesh-to-node mapping
      logger.debug("Mesh-to-node mapping:")
      for (meshIndex, node) in meshToNodeMap.sorted(by: { $0.key < $1.key }) {
        logger.debug("  Mesh \(meshIndex) -> Node '\(node.name)' (has \(node.meshes.count) meshes)")
      }
      logger.debug("Total meshes: \(sceneData.meshes.count), Mapped: \(meshToNodeMap.count)")
      
      return sceneData.meshes
        .enumerated()
        .filter { $0.element.numberOfVertices > 0 }
        .map { (index, mesh) in
          // Get transform from the node that owns this mesh
          let node = meshToNodeMap[index]
          let transformMatrix = node?.calculateWorldTransform() ?? mat4(1)
          
          if node == nil {
            logger.warning("Mesh at index \(index) has no associated node, using identity transform")
          } else {
            // Debug: Print transform for first few meshes
            if index < 3 {
              let m = transformMatrix
              let translation = vec3(m[3].x, m[3].y, m[3].z)
              let localTranslation = vec3(node!.transformation[3].x, node!.transformation[3].y, node!.transformation[3].z)
              logger.debug("Mesh \(index) ('\(mesh.name ?? "unnamed")') transform from node '\(node!.name)':")
              logger.debug("  World translation: (\(translation.x), \(translation.y), \(translation.z))")
              logger.debug("  Local translation: (\(localTranslation.x), \(localTranslation.y), \(localTranslation.z))")
              if let parent = node!.parent {
                let parentTranslation = vec3(parent.transformation[3].x, parent.transformation[3].y, parent.transformation[3].z)
                // Calculate scale from parent transform (length of first 3 columns)
                let parentScaleX = length(vec3(parent.transformation[0].x, parent.transformation[0].y, parent.transformation[0].z))
                let parentScaleY = length(vec3(parent.transformation[1].x, parent.transformation[1].y, parent.transformation[1].z))
                let parentScaleZ = length(vec3(parent.transformation[2].x, parent.transformation[2].y, parent.transformation[2].z))
                logger.debug("  Parent '\(parent.name)' translation: (\(parentTranslation.x), \(parentTranslation.y), \(parentTranslation.z))")
                logger.debug("  Parent scale: (\(parentScaleX), \(parentScaleY), \(parentScaleZ))")
                logger.debug("  Parent has parent: \(parent.parent != nil)")
              } else {
                logger.debug("  Has parent: false")
              }
            }
          }
          
          let instance = MeshInstance(
            sceneData: sceneData, mesh: mesh, transformMatrix: transformMatrix, sceneIdentifier: sceneData.filePath)
          // Store node reference for visibility checking
          instance.node = node
          return instance
        }
    }

    // Load textures with progress on main thread
    let totalTextures = meshInstances.count
    for (index, meshInstance) in meshInstances.enumerated() {
      // Simulate texture loading progress
      onTextureProgress(index + 1, totalTextures, 0.0)

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
      logger.trace("Skeletal mesh: \(boneTransforms.count) bone transforms")
      for (index, transform) in boneTransforms.enumerated() {
        logger.trace("Bone \(index): \(transform)")
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
    guard let material = material else { return }

    // Load material properties
    loadMaterialProperties(material: material)

    // Load all PBR texture types
    if let path = material.diffuseTexturePath {
      loadTextureFromPath(path: path, textureID: &diffuseTexture, hasTexture: &hasDiffuseTexture)
    }
    if let path = material.normalTexturePath {
      loadTextureFromPath(path: path, textureID: &normalTexture, hasTexture: &hasNormalTexture)
    }
    if let path = material.roughnessTexturePath {
      loadTextureFromPath(path: path, textureID: &roughnessTexture, hasTexture: &hasRoughnessTexture)
    }
    if let path = material.metallicTexturePath {
      loadTextureFromPath(path: path, textureID: &metallicTexture, hasTexture: &hasMetallicTexture)
    }
    if let path = material.aoTexturePath {
      loadTextureFromPath(path: path, textureID: &aoTexture, hasTexture: &hasAoTexture)
    }
  }

  private func loadMaterialProperties(material: Material) {
    baseColor = material.baseColor
    metallic = material.metallic
    roughness = material.roughness
    emissive = material.emissive
    opacity = material.opacity
  }

  private func loadTextureFromPath(path: String, textureID: inout GLuint, hasTexture: inout Bool) {
    // Create stable cache key across loads for embedded textures by using scene file path
    let cacheKey = path.hasPrefix("*") ? "\(sceneIdentifier)#\(path)" : path

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.debug("Using cached texture for key \(cacheKey)")
      textureID = cachedTexture
      hasTexture = true
      return
    }

    // Check if it's an embedded texture (starts with "*")
    if path.hasPrefix("*") {
      logger.debug("Loading embedded texture: \(path)")
      loadEmbeddedTexture(texturePath: path, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
    } else {
      logger.debug("Loading external texture: \(path)")
      loadExternalTexture(texturePath: path, textureID: &textureID, hasTexture: &hasTexture)
    }
  }

  private func loadEmbeddedTexture(
    texturePath: String, cacheKey: String, textureID: inout GLuint, hasTexture: inout Bool
  ) {
    // Extract texture index from "*0", "*1", "*10", etc.
    // Drop the "*" prefix and parse the remaining string as an integer
    guard texturePath.hasPrefix("*") else {
      logger.warning("Invalid embedded texture path format: '\(texturePath)' (should start with '*')")
      return
    }
    
    let suffix = String(texturePath.dropFirst())
    guard let textureIndex = Int(suffix) else {
      logger.warning("Failed to parse embedded texture index from '\(texturePath)' (suffix: '\(suffix)')")
      return
    }
    
    guard textureIndex < sceneData.embeddedTextures.count else {
      logger.warning("Embedded texture index \(textureIndex) out of bounds (total: \(sceneData.embeddedTextures.count))")
      return
    }

    logger.debug("Loading embedded texture [\(textureIndex)]: path=\(texturePath), total embedded textures=\(sceneData.embeddedTextures.count)")
    let embeddedTexture = sceneData.embeddedTextures[textureIndex]
    logger.debug("Embedded texture [\(textureIndex)]: data size=\(embeddedTexture.data.count) bytes, formatHint=\(embeddedTexture.formatHint ?? "nil")")
    createOpenGLTexture(
      from: embeddedTexture, texturePath: texturePath, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
  }

  private func loadExternalTexture(texturePath: String, textureID: inout GLuint, hasTexture: inout Bool) {
    // Create cache key for external textures
    let cacheKey = texturePath
    
    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.trace("Using cached external texture for key \(cacheKey)")
      textureID = cachedTexture
      hasTexture = true
      return
    }
    
    // Resolve texture path relative to the GLB file location
    let sceneURL = URL(fileURLWithPath: sceneIdentifier)
    let sceneDirectory = sceneURL.deletingLastPathComponent()
    let textureURL = sceneDirectory.appendingPathComponent(texturePath)
    
    // Try to load from the resolved path
    if let textureData = try? Data(contentsOf: textureURL) {
      loadTextureFromData(textureData, texturePath: texturePath, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
      return
    }
    
    // If that fails, try loading from Bundle.game (for textures in the bundle)
    // Remove any leading path separators and directory components
    let cleanPath = texturePath.hasPrefix("/") ? String(texturePath.dropFirst()) : texturePath
    let pathExtension = URL(fileURLWithPath: cleanPath).pathExtension
    let pathWithoutExtension = URL(fileURLWithPath: cleanPath).deletingPathExtension().lastPathComponent
    if let bundlePath = Bundle.game.path(forResource: cleanPath, ofType: nil) ?? (pathExtension.isEmpty ? nil : Bundle.game.path(forResource: pathWithoutExtension, ofType: pathExtension)) {
      let bundleURL = URL(fileURLWithPath: bundlePath)
      if let textureData = try? Data(contentsOf: bundleURL) {
        loadTextureFromData(textureData, texturePath: texturePath, cacheKey: cacheKey, textureID: &textureID, hasTexture: &hasTexture)
        return
      }
    }
    
    logger.warning("Failed to load external texture: \(texturePath) (tried: \(textureURL.path))")
  }
  
  private func loadTextureFromData(_ data: Data, texturePath: String, cacheKey: String, textureID: inout GLuint, hasTexture: inout Bool) {
    // Create a temporary EmbeddedTexture-like structure
    let dataArray = Array(data)
    let formatHint = URL(fileURLWithPath: texturePath).pathExtension.lowercased()
    
    // Determine format from file extension
    let isPNG = formatHint == "png"
    let isWebP = formatHint == "webp"
    let isJPEG = formatHint == "jpg" || formatHint == "jpeg"
    
    do {
      if isPNG {
        let image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: dataArray) { _ in }
        image.bytes.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          hasTexture = true
        }
      } else if isWebP {
        let image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          hasTexture = true
        }
      } else if isJPEG {
        let image = try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGB,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
          hasTexture = true
        }
      } else {
        // Try generic loader
        let image = try ImageFormats.Image<ImageFormats.RGBA>.load(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          hasTexture = true
        }
      }
      
      if hasTexture {
        // Cache the texture
        TextureCache.shared.cacheTexture(textureID, for: cacheKey)
        logger.trace("Loaded external texture: \(texturePath)")
      }
    } catch {
      logger.error("Failed to decode external texture \(texturePath): \(error)")
    }
  }


  private func createOpenGLTexture(
    from embeddedTexture: EmbeddedTexture,
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

    let data = embeddedTexture.data
    let dataArray = Array(data)
    let formatHint = embeddedTexture.formatHint?.lowercased() ?? ""
    
    logger.debug("Creating OpenGL texture from embedded data: formatHint=\(formatHint), data size=\(data.count) bytes")

    do {
      // Try to determine format from hint
      if formatHint.contains("png") {
        let image = try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: dataArray) { progress in
          //print("Loading PNG texture: \(progress * 100)%")
        }
        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      } else if formatHint.contains("webp") {
        let image = try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      } else if formatHint.contains("jpg") || formatHint.contains("jpeg") {
        let image = try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGB,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      } else {
        // Try generic loader
        let image = try ImageFormats.Image<ImageFormats.RGBA>.load(from: dataArray)
        image.bytes.withUnsafeBytes { bytes in
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      }
    } catch {
      logger.error("Failed to decode texture \(texturePath): \(error)")
      glBindTexture(GL_TEXTURE_2D, 0)
      return
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
    logger.debug("Cached texture for key \(cacheKey), textureID=\(textureID), hasTexture=\(hasTexture)")
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
  func getTransformMatrix(for meshIndex: Int) -> mat4 {
    return findMeshTransform(meshIndex: meshIndex, node: rootNode, parentTransform: mat4(1))
  }

  private func findMeshTransform(meshIndex: Int, node: Node, parentTransform: mat4) -> mat4 {
    // Get this node's transformation matrix
    let nodeTransform = node.transformation
    let globalTransform = parentTransform * nodeTransform

    // Check if this node contains the mesh
    if node.meshes.contains(meshIndex) {
      return globalTransform
    }

    // Search in child nodes
    for childNode in node.children {
      let result = findMeshTransform(meshIndex: meshIndex, node: childNode, parentTransform: globalTransform)
      if result != mat4(1) {
        return result
      }
    }

    return mat4(1)  // Not found
  }
}

// MARK: - Mesh helpers for packing GPU data

extension Mesh {
  func makeVertices() -> [MeshVertex] {
    var result: [MeshVertex] = []
    result.reserveCapacity(numberOfVertices)

    // Create bone weight mapping for efficient lookup (only if mesh has bones)
    let boneWeightMap = numberOfBones > 0 ? createBoneWeightMap() : [:]

    // Debug: Print bone information
    if numberOfBones > 0 {
      logger.trace("Mesh has \(numberOfBones) bones, weight map has \(boneWeightMap.count) entries")
      for (index, bone) in bones.enumerated() {
        logger.trace("Bone \(index): \(bone.name ?? "Unknown") with \(bone.weights.count) weights")
      }
    }

    for i in 0..<numberOfVertices {
      let p = (
        positions[i * 3 + 0],
        positions[i * 3 + 1],
        positions[i * 3 + 2]
      )
      let n: (Float, Float, Float)
      if let normals = normals, normals.count >= (i * 3 + 3) {
        n = (normals[i * 3 + 0], normals[i * 3 + 1], normals[i * 3 + 2])
      } else {
        n = (0, 0, 0)
      }
      let t: (Float, Float)
      if let uvs = uvs, uvs.count >= (i * 2 + 2) {
        t = (uvs[i * 2 + 0], uvs[i * 2 + 1])
      } else {
        t = (0, 0)
      }
      let tangent: (Float, Float, Float)
      if let tangents = tangents, tangents.count >= (i * 3 + 3) {
        tangent = (tangents[i * 3 + 0], tangents[i * 3 + 1], tangents[i * 3 + 2])
      } else {
        tangent = (0, 0, 0)
      }
      let bitangent: (Float, Float, Float)
      if let bitangents = bitangents, bitangents.count >= (i * 3 + 3) {
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
  private func createBoneWeightMap() -> [Int: [(boneIndex: Int, weight: Float)]] {
    var weightMap: [Int: [(boneIndex: Int, weight: Float)]] = [:]

    // Initialize with empty arrays for all vertices
    for i in 0..<numberOfVertices {
      weightMap[i] = []
    }

    // Process each bone's weights with error handling
    for (boneIndex, bone) in bones.enumerated() {
      // Check if bone has valid weight data
      guard !bone.weights.isEmpty else { continue }

      for weight in bone.weights {
        let vertexIndex = weight.vertexIndex
        if vertexIndex < numberOfVertices {
          weightMap[vertexIndex, default: []].append((boneIndex: boneIndex, weight: weight.weight))
        }
      }
    }

    return weightMap
  }

  /// Get bone indices and weights for a specific vertex
  private func getBoneData(for vertexIndex: Int, boneWeightMap: [Int: [(boneIndex: Int, weight: Float)]]) -> (
    (UInt8, UInt8, UInt8, UInt8), (Float, Float, Float, Float)
  ) {
    guard let vertexWeights = boneWeightMap[vertexIndex], !vertexWeights.isEmpty else {
      // No bone weights for this vertex
      return ((0, 0, 0, 0), (0, 0, 0, 0))
    }

    // Sort weights by weight value (descending) and take up to 4
    let sortedWeights = vertexWeights.sorted { $0.weight > $1.weight }.prefix(4)

    var indices: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var weights: (Float, Float, Float, Float) = (0, 0, 0, 0)

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
