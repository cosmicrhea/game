import ImageFormats
import GLTF

// Flag to disable HDRI loading for now
private let enableHDRI = false

/// Errors that can occur during texture loading
enum TextureLoadError: Error {
  case invalidPath(String)
  case fileNotFound(String)
  case uploadFailed
  case decodeFailed(String)
}

/// Decoded image data ready for GPU upload
enum DecodedImage {
  case rgba(image: ImageFormats.Image<ImageFormats.RGBA>)
  case rgb(image: ImageFormats.Image<ImageFormats.RGB>)
  
  var width: Int {
    switch self {
    case .rgba(let image): return image.width
    case .rgb(let image): return image.width
    }
  }
  
  var height: Int {
    switch self {
    case .rgba(let image): return image.height
    case .rgb(let image): return image.height
    }
  }
}

/// Global texture cache to avoid loading duplicate textures
final class TextureCache: @unchecked Sendable {
  static let shared = TextureCache()

  private var cache: [String: GLuint] = [:]
  private var inflightLoads: [String: Task<(GLuint, Bool, MeshInstance.AlphaProfile?), Error>] = [:]
  private let lock = NSLock()

  private init() {}

  /// Get a cached texture by path, or nil if not cached
  nonisolated func getCachedTexture(for path: String) -> GLuint? {
    lock.lock()
    defer { lock.unlock() }
    return cache[path]
  }
  
  /// Get an in-flight load task if one exists
  nonisolated func getInflightLoad(for path: String) -> Task<(GLuint, Bool, MeshInstance.AlphaProfile?), Error>? {
    lock.lock()
    defer { lock.unlock() }
    return inflightLoads[path]
  }
  
  /// Register an in-flight load task
  nonisolated func registerInflightLoad(_ task: Task<(GLuint, Bool, MeshInstance.AlphaProfile?), Error>, for path: String) {
    lock.lock()
    defer { lock.unlock() }
    inflightLoads[path] = task
  }
  
  /// Remove an in-flight load task
  nonisolated func removeInflightLoad(for path: String) {
    lock.lock()
    defer { lock.unlock() }
    inflightLoads.removeValue(forKey: path)
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
    let texturesToDelete = Array(cache.values)
    cache.removeAll()
    inflightLoads.removeAll()
    lock.unlock()
    
    // Delete textures on main thread (OpenGL requirement)
    if !texturesToDelete.isEmpty {
      if Thread.isMainThread {
        for texture in texturesToDelete {
          var tex = texture
          glDeleteTextures(1, &tex)
        }
      } else {
        DispatchQueue.main.async {
          for texture in texturesToDelete {
            var tex = texture
            glDeleteTextures(1, &tex)
          }
        }
      }
    }
  }

  deinit {
    clearCache()
  }
}

/// Global lock to serialize OpenGL texture uploads (prevents GL_INVALID_OPERATION from concurrent uploads)
private let textureUploadLock = NSLock()

struct MeshVertex {
  var position: (Float, Float, Float)
  var normal: (Float, Float, Float)
  var uv: (Float, Float)
  var uv1: (Float, Float)
  var tangent: (Float, Float, Float)
  var bitangent: (Float, Float, Float)

  // Skeletal animation data
  var boneIndices: (Int32, Int32, Int32, Int32)  // Up to 4 bone indices per vertex (Int32 for GL_INT)
  var boneWeights: (Float, Float, Float, Float)  // Corresponding weights
}

@MainActor
class MeshInstance {

  let sceneData: Scene
  let mesh: Mesh
  let transformMatrix: mat4
  private let sceneIdentifier: String

  // Helper to get bundle-relative path for logging
  private var bundleRelativeScenePath: String {
    guard let resourceURL = Bundle.game.resourceURL else {
      return sceneIdentifier
    }
    let sceneURL = URL(fileURLWithPath: sceneIdentifier)
    let resourcePath = resourceURL.path
    if sceneURL.path.hasPrefix(resourcePath) {
      let relativePath = String(sceneURL.path.dropFirst(resourcePath.count + 1))
      return relativePath
    }
    return sceneIdentifier
  }

  // Helper to get context string for texture logging (node name, material name, mesh name)
  private func getTextureContext(material: Material? = nil) -> String {
    var parts: [String] = []
    
    // Add material name if available
    let materialName = material?.name ?? self.material?.name
    if let materialName, !materialName.isEmpty {
      parts.append(materialName)
    }
    
    // Prioritize node name
    if let nodeName = node?.name, !nodeName.isEmpty {
      parts.append(nodeName)
    }
    
    // Add mesh name if available and different from node name
    if let meshName = mesh.name, !meshName.isEmpty {
      if node?.name != meshName {
        parts.append(meshName)
      }
    }
    
    if parts.isEmpty {
      return ""
    }
    return " (\(parts.joined(separator: ", ")))"
  }


  // Rendering programs (cached by shader pair)
  private struct ProgramSet {
    let opaque: GLProgram
    let cutout: GLProgram
    let blend: GLProgram
    let shadowMatte: GLProgram
  }
  private let programs: ProgramSet

  var VAO: GLuint = 0
  var VBO: GLuint = 0
  var EBO: GLuint = 0

  // Skeletal animation support
  var boneTransforms: [mat4] = []
  private var boneNames: [String] = []
  var isSkeletalMesh: Bool = false

  // Animation - uses shared controller for node transforms
  // Bone transforms are calculated per-mesh from shared node transforms

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
  var alphaMode: GLTFAlphaMode = .opaque
  var alphaCutoff: Float = 0.5
  var isDoubleSided: Bool = false
  var depthBiasRole: Material.DepthBiasRole = .none  // Explicit depth bias role (no name-based heuristics)
  
  // Texture alpha analysis for BLEND participation logic
  var hasNonOpaqueAlpha: Bool = false  // True if baseColorTexture has alpha < 0.999
  var alphaProfile: AlphaProfile? = nil  // Alpha distribution profile for automatic classification
  
  // Render mode derived from alpha profile (computed once, used everywhere)
  // Clean 3-mode transparency system: Opaque, CutoutCoverage, OverlayBlend
  // Translucent remains for truly translucent materials (glass, etc.)
  enum RenderMode {
    case opaque          // minA > 0.98: skin/body/clothes (opaque pass, depth write ON, blending OFF)
    case cutoutCoverage  // pctMid <= 0.01: hair cards/foliage (opaque pass, depth write ON, alpha-to-coverage or discard)
    case overlayBlend    // pctMid > 0.01: makeup/decals/brows (transparent pass, depth write OFF, blending ON, no dither/cutoff)
    case translucent     // Legacy: truly translucent materials (glass, etc.) - transparent pass, sorted, depth write OFF
  }
  var renderMode: RenderMode = .opaque  // Final render mode for this material
  var useAlphaHash: Bool = false  // Use alpha-hashed dither for cutoutCoverage (derived from renderMode)
  var materialName: String? = nil  // Store material name for debugging
  private var lastLoggedRenderPass: String? = nil
  private var lastLoggedRenderMode: RenderMode? = nil
  private var didWarnNoMSAAForCutout: Bool = false
  private var didLogUVBounds: Bool = false
  private var didLogMissingTexcoord0: Bool = false

  // Node reference for checking visibility (optional)
  weak var node: Node?

  init(sceneData: Scene, mesh: Mesh, transformMatrix: mat4 = mat4(1), sceneIdentifier: String) {
    self.sceneData = sceneData
    self.mesh = mesh
    self.transformMatrix = transformMatrix
    self.sceneIdentifier = sceneIdentifier

    // Create shader programs - use skeletal vertex shader if mesh has bones
    self.isSkeletalMesh = mesh.numberOfBones > 0
    let vertexName = isSkeletalMesh ? "Common/skeletal" : "Common/basic 2"
    self.programs = ProgramSet(
      opaque: try! GLProgram.cached(vertexName, "Common/pbr_opaque"),
      cutout: try! GLProgram.cached(vertexName, "Common/pbr_cutout"),
      blend: try! GLProgram.cached(vertexName, "Common/pbr_blend"),
      shadowMatte: try! GLProgram.cached(vertexName, "Common/shadow_matte")
    )
    if isSkeletalMesh {
      initializeBoneData()
    }

    glGenVertexArrays(1, &VAO)
    GLStats.incrementBuffers()
    glGenBuffers(1, &VBO)
    GLStats.incrementBuffers()
    glGenBuffers(1, &EBO)
    GLStats.incrementBuffers()

    logUVBoundsIfNeeded()

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
    if let uvs = mesh.uvs, !uvs.isEmpty {
      glEnableVertexAttribArray(2)
      glVertexAttribPointer(
        2, 2, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
        UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.uv)!))
    } else {
      glDisableVertexAttribArray(2)
      glVertexAttrib2f(2, 0, 0)
    }

    // vertex uv1
    if let uvs1 = mesh.uvs1, !uvs1.isEmpty {
      glEnableVertexAttribArray(7)
      glVertexAttribPointer(
        7, 2, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
        UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.uv1)!))
    } else {
      glDisableVertexAttribArray(7)
      glVertexAttrib2f(7, 0, 0)
    }

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
    // CRITICAL: Use glVertexAttribIPointer (with I) for integer attributes!
    // LearnOpenGL: "We are using glVertexAttribIPointer and we passed GL_INT as third parameter"
    glEnableVertexAttribArray(5)
    glVertexAttribIPointer(
      5, 4, GL_INT, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.boneIndices)!))

    // bone weights (4 components as floats)
    glEnableVertexAttribArray(6)
    glVertexAttribPointer(
      6, 4, GL_FLOAT, false, GLsizei(MemoryLayout<MeshVertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \MeshVertex.boneWeights)!))

    glBindVertexArray(0)

    // Load material properties so baseColor is available for rendering
    // (textures will be loaded asynchronously later via loadTextures())
    if let material {
      loadMaterialProperties(material: material)
    }

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

  // MARK: - Animation

  /// Update bone transforms from shared animated node transforms
  /// Called by the animation controller after it updates node transforms
  /// Matches LearnOpenGL's recursive CalculateBoneTransform approach
  func updateBoneTransforms(animatedNodeTransforms: [String: mat4]) {
    guard isSkeletalMesh else {
      // For non-skeletal meshes, we could apply node transforms here if needed
      // But for now, skeletal animation is the main use case
      return
    }

    // Create a map from bone name to bone index and offset matrix
    var boneMap: [String: (index: Int, offsetMatrix: mat4)] = [:]
    for (index, bone) in mesh.bones.enumerated() {
      if let boneName = bone.name {
        boneMap[boneName] = (index: index, offsetMatrix: bone.offsetMatrix)
      }
    }

    // Verify bone map
    if boneMap.count != mesh.numberOfBones {
      logger.warning("⚠️ Bone map count (\(boneMap.count)) != mesh.numberOfBones (\(mesh.numberOfBones))")
    }

    // CRITICAL: Reset all bone transforms to identity first (like LearnOpenGL does)
    // This ensures bones that aren't found in the hierarchy get identity instead of stale values
    for i in 0..<boneTransforms.count {
      boneTransforms[i] = mat4(1)
    }

    // LearnOpenGL approach: Recursively calculate bone transforms starting from root
    // Only processes nodes that are bones (checks if node name is in boneMap)
    var dummyOutput: [Int: mat4]? = nil
    calculateBoneTransform(
      node: sceneData.rootNode,
      parentTransform: mat4(1),
      animatedNodeTransforms: animatedNodeTransforms.isEmpty ? [:] : animatedNodeTransforms,
      boneMap: boneMap,
      outputTransforms: &dummyOutput
    )

    // Verify bones were processed
    var bonesNotProcessed: [String] = []
    for (index, bone) in mesh.bones.enumerated() {
      // A bone is "processed" if its transform is NOT identity (was set by calculateBoneTransform)
      if boneTransforms[index] == mat4(1), let boneName = bone.name {
        bonesNotProcessed.append(boneName)
      }
    }
    if !bonesNotProcessed.isEmpty {
      logger.warning("⚠️ Bones NOT processed: \(bonesNotProcessed.prefix(5))")
    }
  }

  /// LearnOpenGL's CalculateBoneTransform approach:
  /// Recursively traverse node hierarchy, only process nodes that are bones
  /// For each bone: get local transform → multiply with parent → multiply with offsetMatrix
  private func calculateBoneTransform(
    node: Node,
    parentTransform: mat4,
    animatedNodeTransforms: [String: mat4],
    boneMap: [String: (index: Int, offsetMatrix: mat4)],
    outputTransforms: inout [Int: mat4]?
  ) {
    // Check if this node is a bone (matches LearnOpenGL's bone check)
    let nodeName = node.name
    let isBone = !nodeName.isEmpty && boneMap[nodeName] != nil

    // Get local transform: use animated transform if available, otherwise use bind pose
    // CRITICAL: GLTF animations might work differently than Assimp!
    let localTransform: mat4
    if let animatedTransform = animatedNodeTransforms[nodeName] {
      // GLTF animations provide absolute transforms (they replace bind pose)
      // But maybe we need to handle coordinate system conversion?
      localTransform = animatedTransform
    } else {
      // Use bind pose transform from node
      localTransform = node.transformation
    }

    // Calculate global transform: parentTransform * localTransform
    // For column-major matrices, this order is correct
    // BUT: Maybe for GLTF animated transforms, we need a different order?
    // Standard (bind pose): parentTransform * localTransform
    // Try reverse for animated: localTransform * parentTransform (probably wrong)
    let globalTransform = parentTransform * localTransform

    // If this node is a bone, calculate final bone matrix
    if isBone, let boneInfo = boneMap[nodeName] {
      let boneIndex = boneInfo.index
      guard boneIndex < boneTransforms.count else { return }

      // LearnOpenGL formula: finalBoneMatrix = globalTransformation * offsetMatrix
      let finalBoneMatrix = globalTransform * boneInfo.offsetMatrix
      boneTransforms[boneIndex] = finalBoneMatrix
      if var output = outputTransforms {
        output[boneIndex] = finalBoneMatrix
        outputTransforms = output
      }

    }

    // Recursively process children (LearnOpenGL passes globalTransform as new parentTransform)
    for child in node.children {
      calculateBoneTransform(
        node: child,
        parentTransform: globalTransform,
        animatedNodeTransforms: animatedNodeTransforms,
        boneMap: boneMap,
        outputTransforms: &outputTransforms
      )
    }
  }

  deinit {
    // OpenGL calls MUST happen on the main thread
    // If we're being deallocated on a background thread, dispatch to main
    let vao = VAO
    let vbo = VBO
    let ebo = EBO
    let envMap = environmentMap
    
    if vao != 0 || vbo != 0 || ebo != 0 || envMap != 0 {
      // Check if we're on the main thread
      if Thread.isMainThread {
        // Safe to delete immediately
        if vao != 0 {
          var v = vao
          glDeleteVertexArrays(1, &v)
          GLStats.decrementBuffers()
        }
        if vbo != 0 {
          var v = vbo
          glDeleteBuffers(1, &v)
          GLStats.decrementBuffers()
        }
        if ebo != 0 {
          var v = ebo
          glDeleteBuffers(1, &v)
          GLStats.decrementBuffers()
        }
        if envMap != 0 {
          var t = envMap
          glDeleteTextures(1, &t)
        }
      } else {
        // Schedule deletion on main thread
        DispatchQueue.main.async {
          if vao != 0 {
            var v = vao
            glDeleteVertexArrays(1, &v)
            GLStats.decrementBuffers()
          }
          if vbo != 0 {
            var v = vbo
            glDeleteBuffers(1, &v)
            GLStats.decrementBuffers()
          }
          if ebo != 0 {
            var v = ebo
            glDeleteBuffers(1, &v)
            GLStats.decrementBuffers()
          }
          if envMap != 0 {
            var t = envMap
            glDeleteTextures(1, &t)
          }
        }
      }
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
    onTextureProgress: @escaping @Sendable (Int, Int, Float, String?) -> Void,
    loadTextures: Bool = true
  ) async throws -> [MeshInstance] {

    // Load GLTF document on background thread with progress
    let sceneData = try await Task.detached {
      let scenePath = Bundle.game.path(forResource: path, ofType: "glb")!
      let url = URL(fileURLWithPath: scenePath)

      // Use nonisolated callback to avoid Sendable issues
      let gltfDocument = try await GLTFDocument(contentsOf: url) { @Sendable progress in
        Task { @MainActor in
          onSceneProgress(Float(progress))
        }
      }

      // Convert to our Scene (also on background thread)
      return Scene(gltfDocument, filePath: scenePath)
    }.value

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
    logger.trace(
      "Root node: '\(sceneData.rootNode.name)', children: \(sceneData.rootNode.children.count), meshes: \(sceneData.rootNode.meshes.count)"
    )
    logger.trace(
      "Root node transform translation: (\(sceneData.rootNode.transformation[3].x), \(sceneData.rootNode.transformation[3].y), \(sceneData.rootNode.transformation[3].z))"
    )

    // Debug: Print mesh-to-node mapping
    logger.trace("Mesh-to-node mapping:")
    for (meshIndex, node) in meshToNodeMap.sorted(by: { $0.key < $1.key }) {
      logger.trace("  Mesh \(meshIndex) -> Node '\(node.name)' (has \(node.meshes.count) meshes)")
    }
      logger.trace("Total meshes: \(sceneData.meshes.count), Mapped: \(meshToNodeMap.count)")

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
            let localTranslation = vec3(
              node!.transformation[3].x, node!.transformation[3].y, node!.transformation[3].z)
            logger.trace("Mesh \(index) ('\(mesh.name ?? "unnamed")') transform from node '\(node!.name)':")
            logger.trace("  World translation: (\(translation.x), \(translation.y), \(translation.z))")
            logger.trace("  Local translation: (\(localTranslation.x), \(localTranslation.y), \(localTranslation.z))")
            if let parent = node!.parent {
              let parentTranslation = vec3(
                parent.transformation[3].x, parent.transformation[3].y, parent.transformation[3].z)
              // Calculate scale from parent transform (length of first 3 columns)
              let parentScaleX = length(
                vec3(parent.transformation[0].x, parent.transformation[0].y, parent.transformation[0].z))
              let parentScaleY = length(
                vec3(parent.transformation[1].x, parent.transformation[1].y, parent.transformation[1].z))
              let parentScaleZ = length(
                vec3(parent.transformation[2].x, parent.transformation[2].y, parent.transformation[2].z))
              logger.trace(
                "  Parent '\(parent.name)' translation: (\(parentTranslation.x), \(parentTranslation.y), \(parentTranslation.z))"
              )
              logger.trace("  Parent scale: (\(parentScaleX), \(parentScaleY), \(parentScaleZ))")
              logger.trace("  Parent has parent: \(parent.parent != nil)")
            } else {
              logger.trace("  Has parent: false")
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

    // Load textures with progress using TaskGroup with concurrency limit (if requested)
    if loadTextures {
      let totalTextures = meshInstances.count
      let maxConcurrentLoads = 3
      
      await withTaskGroup(of: (Int, String?).self) { group in
        var activeLoads = 0
        var nextIndex = 0
        
        // Process all mesh instances
        while nextIndex < meshInstances.count || activeLoads > 0 {
          // Start new tasks if we're below the limit
          while activeLoads < maxConcurrentLoads && nextIndex < meshInstances.count {
            let index = nextIndex
            let meshInstance = meshInstances[index]
            let nodeName = meshInstance.node?.name
            
            group.addTask {
              // Report starting
              await MainActor.run {
                onTextureProgress(index + 1, totalTextures, 0.0, nodeName)
              }
              
              // Load textures for this mesh
              await meshInstance.loadTextures()
              
              // Report completion
              await MainActor.run {
                onTextureProgress(index + 1, totalTextures, 1.0, nodeName)
              }
              
              return (index, nodeName)
            }
            
            activeLoads += 1
            nextIndex += 1
          }
          
          // Wait for one task to complete
          if let _ = await group.next() {
            activeLoads -= 1
          }
        }
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
      fillLightDirection: fillLightDirection, fillLightColor: fillLightColor, fillLightIntensity: fillLightIntensity,
      effectiveRenderMode: renderMode,
      showFinalAlpha: false, showClassification: false, cutoutThreshold: 0.5, showUVDebug: false, showUVRaw: false,
      renderPassName: "DefaultPass",
      useAlphaHash: false, useAlphaToCoverage: false, usePolygonOffset: false,
      debugForceTransparentColor: false)
  }

  private func programFor(effectiveRenderMode: RenderMode, isShadowCatcher: Bool) -> GLProgram {
    if isShadowCatcher {
      return programs.shadowMatte
    }
    switch effectiveRenderMode {
    case .opaque:
      return programs.opaque
    case .cutoutCoverage:
      return programs.cutout
    case .overlayBlend, .translucent:
      return programs.blend
    }
  }

  func draw(
    projection: mat4, view: mat4, modelMatrix: mat4, cameraPosition: vec3, lightDirection: vec3, lightColor: vec3,
    lightIntensity: Float, fillLightDirection: vec3, fillLightColor: vec3, fillLightIntensity: Float,
    diffuseOnly: Bool = false, showTextureDebug: Bool = false,
    effectiveRenderMode: RenderMode,
    showFinalAlpha: Bool = false, showClassification: Bool = false, cutoutThreshold: Float = 0.5,
    showUVDebug: Bool = false, showUVRaw: Bool = false,
    renderPassName: String = "UnknownPass",
    useAlphaHash: Bool = false, useAlphaToCoverage: Bool = false, usePolygonOffset: Bool = false,
    useFixedRenderState: Bool = false,
    debugForceTransparentColor: Bool = false,  // Temporary debug: force cyan with 0.5 alpha
    shadowIntensity: Float = 0.15,
    shadowMapTextureUnit: GLenum? = nil, lightSpaceMatrix: mat4? = nil,
    isShadowCatcher: Bool = false,
    shadowCatcherDebugColor: Bool = false  // Debug: render shadow catchers as solid color
  ) {
    let program = programFor(effectiveRenderMode: effectiveRenderMode, isShadowCatcher: isShadowCatcher)
    program.use()

    logDrawIfNeeded(passName: renderPassName, effectiveRenderMode: effectiveRenderMode)

    var effectiveUseAlphaToCoverage = effectiveRenderMode == .cutoutCoverage ? useAlphaToCoverage : false
    var effectiveUseAlphaHash = useAlphaHash
    var effectiveCutoutThreshold = cutoutThreshold
    if effectiveRenderMode == .cutoutCoverage && useAlphaToCoverage {
      var sampleCount: GLint = 0
      glGetIntegerv(GL_SAMPLES, &sampleCount)
      let multisampleEnabled = glIsEnabled(GL_MULTISAMPLE) == GLboolean(GL_TRUE)
      let msaaEnabled = sampleCount > 1 && multisampleEnabled
      logger.trace(
        "🧪 MSAA state for '\(materialName ?? "<unnamed>")': GL_SAMPLES=\(sampleCount), GL_MULTISAMPLE=\(multisampleEnabled ? "ON" : "OFF")"
      )
      if !msaaEnabled {
        effectiveUseAlphaToCoverage = false
        effectiveUseAlphaHash = true
        if !didWarnNoMSAAForCutout {
          logger.warning(
            "⚠️ CutoutCoverage requested alpha-to-coverage without MSAA; falling back to alpha-hash for '\(materialName ?? "<unnamed>")'"
          )
          didWarnNoMSAAForCutout = true
        }
      }
    }

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

    // Set debug uniforms (all decisions made in ModelViewer, just pass through)
    program.setBool("diffuseOnly", value: diffuseOnly)
    program.setBool("showTextureDebug", value: showTextureDebug)
    program.setBool("showUVDebug", value: showUVDebug)
    program.setBool("showUVRaw", value: showUVRaw)
    let baseColorTexCoord = material?.diffuseTexture?.texCoord ?? 0
    program.setInt("baseColorTexCoord", value: Int32(baseColorTexCoord))
    let missingTexcoord0 = baseColorTexCoord == 0 && (mesh.uvs == nil || mesh.uvs?.isEmpty == true)
    program.setBool("missingTexcoord0", value: missingTexcoord0)
    if missingTexcoord0 && !didLogMissingTexcoord0 {
      didLogMissingTexcoord0 = true
      logger.error("❌ Mesh '\(mesh.name ?? "<unnamed>")' missing TEXCOORD_0 while baseColorTexCoord=0.")
    }
    program.setBool("isDoubleSided", value: isDoubleSided)
    program.setBool("useAlphaHash", value: effectiveUseAlphaHash)
    program.setBool("isOverlayBlend", value: effectiveRenderMode == .overlayBlend)
    // Pass renderModeId for accurate classification debug (not alphaMode - glTF often marks opaque as BLEND)
    let renderModeId: Int32
    switch effectiveRenderMode {
    case .opaque: renderModeId = 0
    case .cutoutCoverage: renderModeId = 1
    case .overlayBlend: renderModeId = 2
    case .translucent: renderModeId = 3
    }
    program.setInt("renderModeId", value: renderModeId)
    program.setFloat("cutoutThreshold", value: effectiveCutoutThreshold)
    program.setBool("showFinalAlpha", value: showFinalAlpha)
    program.setBool("showClassification", value: showClassification)
    program.setBool("useAlphaToCoverage", value: effectiveUseAlphaToCoverage)
    program.setBool("debugForceTransparentColor", value: debugForceTransparentColor)  // Temporary debug mode

    // Set material properties
    program.setVec3("baseColor", value: (baseColor.x, baseColor.y, baseColor.z))
    program.setFloat("metallic", value: metallic)
    program.setFloat("roughness", value: roughness)
    program.setVec3("emissive", value: (emissive.x, emissive.y, emissive.z))
    program.setFloat("opacity", value: opacity)
    
    // Set alpha mode (0=OPAQUE, 1=MASK, 2=BLEND)
    let alphaModeInt: Int32
    switch alphaMode {
    case .opaque:
      alphaModeInt = 0
    case .mask:
      alphaModeInt = 1
    case .blend:
      alphaModeInt = 2
    @unknown default:
      alphaModeInt = 0
    }
    program.setInt("alphaMode", value: alphaModeInt)
    program.setFloat("alphaCutoff", value: alphaCutoff)

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

    // Bind shadow map
    if let shadowMapTextureUnit = shadowMapTextureUnit, let lightSpaceMatrix = lightSpaceMatrix {
      program.setInt("shadowMap", value: Int32(shadowMapTextureUnit - GL_TEXTURE0))
      program.setBool("hasShadowMap", value: true)
      program.setMat4("lightSpaceMatrix", value: lightSpaceMatrix)
      glActiveTexture(shadowMapTextureUnit)
      // Shadow map texture is bound by caller
    } else {
      program.setBool("hasShadowMap", value: false)
    }
    
    // Set shadow catcher flag
    program.setBool("isShadowCatcher", value: isShadowCatcher)
    
    // Shadow catchers use full intensity; lit objects use the caller's intensity.
    let effectiveShadowIntensity: Float = isShadowCatcher ? 1.0 : shadowIntensity
    program.setFloat("shadowIntensity", value: effectiveShadowIntensity)
    
    // Set debug color flag for shadow catchers
    program.setBool("shadowCatcherDebugColor", value: shadowCatcherDebugColor)

    // Use pre-computed render mode (derived from alpha profile)
    // This ensures consistent behavior across logging, pass routing, and GL state
    // renderMode drives GL state, not alphaMode
    
    let shouldPreserveGLState = isShadowCatcher || useFixedRenderState
    
    // Save and configure OpenGL state for proper rendering
    let wasBlendEnabled = glIsEnabled(GL_BLEND)
    let wasDepthTestEnabled = glIsEnabled(GL_DEPTH_TEST)
    let wasCullFaceEnabled = glIsEnabled(GL_CULL_FACE)
    let wasPolygonOffsetEnabled = glIsEnabled(GL_POLYGON_OFFSET_FILL)
    let wasAlphaToCoverageEnabled = glIsEnabled(GL_SAMPLE_ALPHA_TO_COVERAGE)
    var savedDepthMask: GLboolean = true
    glGetBooleanv(GL_DEPTH_WRITEMASK, &savedDepthMask)
    
    if !shouldPreserveGLState {
      // Handle double-sided rendering (for hair cards like eyebrows/eyelashes)
      if isDoubleSided {
        glDisable(GL_CULL_FACE)
      } else {
        glEnable(GL_CULL_FACE)
        glCullFace(GL_BACK)
      }
      
      // Configure GL state based on effectiveRenderMode (may be overridden by transparencyDebugMode)
      switch effectiveRenderMode {
      case .opaque:
        // Opaque: no blending, depth test ON, depth write ON
        // Standard opaque rendering - depth write ON for proper occlusion
        glDisable(GL_BLEND)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glDepthMask(true)  // Depth write ON for opaque
        glDisable(GL_POLYGON_OFFSET_FILL)  // No polygon offset for opaque
        
      case .cutoutCoverage:
        // CutoutCoverage/hair cards: use alpha-to-coverage (MSAA) or dither, no blending, depth test ON, depth write ON, opaque pass
        // This avoids transparent self-occlusion between overlapping alpha cards
        glDisable(GL_BLEND)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glDepthMask(true)  // Depth write ON for stable hair rendering
        
        // Enable alpha-to-coverage (MSAA) for smooth coverage without visible striping
        // This matches Godot/Apple behavior and fixes coverage artifacts on hair cards
        if effectiveUseAlphaToCoverage {
          glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE)
        } else {
          glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE)
        }
        
        // Enable polygon offset for cutoutCoverage haircards to fix coplanar z-fighting with skin
        // Character shaders do not write gl_FragDepth, so polygon offset works correctly
        // Reduced magnitude to fix hairline black fringe (was -2.0, now -0.5)
        if usePolygonOffset {
          glEnable(GL_POLYGON_OFFSET_FILL)
          glPolygonOffset(-0.5, -0.5)  // Reduced offset to fix hairline fringe
        } else {
          glDisable(GL_POLYGON_OFFSET_FILL)
        }
        
      case .overlayBlend:
        // OverlayBlend: makeup/decals/eyebrows - decal-style overlay rendering
        // Alpha is a coverage mask, not true transparency - render as decal overlay
        // Depth test ON - clip against skin geometry (don't render through face)
        // Depth write OFF - don't occlude things behind (decals don't write depth)
        // Blending ON - alpha is coverage mask for blending
        glEnable(GL_DEPTH_TEST)   // Depth test ON - clip against skin
        glDepthFunc(GL_LEQUAL)    // Standard depth comparison
        glDepthMask(false)         // Depth write OFF (decals don't occlude)
        glEnable(GL_BLEND)         // Enable blending
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)  // Standard alpha blending
        glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE)  // No alpha-to-coverage for smooth blending
        glDisable(GL_POLYGON_OFFSET_FILL)  // No polygon offset for overlay blend decals
        
      case .translucent:
        // True translucent: normal BLEND, sorted, depth write OFF
        // Only enable blending if material actually needs it
        let needsBlending = opacity < 0.999 || hasNonOpaqueAlpha
        if needsBlending {
          glEnable(GL_BLEND)
          glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)  // Standard alpha blending
          glEnable(GL_DEPTH_TEST)
          glDepthFunc(GL_LEQUAL)
          glDepthMask(false)  // Depth write OFF for transparent objects
        } else {
          // Translucent material but effectively opaque: render as opaque
          glDisable(GL_BLEND)
          glEnable(GL_DEPTH_TEST)
          glDepthFunc(GL_LEQUAL)
          glDepthMask(true)
        }
      }
    } else {
      // Preserve caller's blend/depth state, but still respect per-mesh culling and offsets.
      if isDoubleSided {
        glDisable(GL_CULL_FACE)
      } else {
        glEnable(GL_CULL_FACE)
        glCullFace(GL_BACK)
      }
      if usePolygonOffset {
        glEnable(GL_POLYGON_OFFSET_FILL)
        glPolygonOffset(-0.5, -0.5)
      } else {
        glDisable(GL_POLYGON_OFFSET_FILL)
      }
    }

    // Verify we're using filled triangles (GL_TRIANGLES with default GL_FILL mode)
    // Polygon offset (GL_POLYGON_OFFSET_FILL) only affects filled primitives
    // This draw call uses GL_TRIANGLES, which is correct for polygon offset
    glBindVertexArray(VAO)
    glDrawElements(GL_TRIANGLES, GLsizei(mesh.faces.count * 3), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)

    // Restore OpenGL state if we changed it
    if !shouldPreserveGLState {
      switch effectiveRenderMode {
      case .opaque:
        // Restore blending state
        if wasBlendEnabled { glEnable(GL_BLEND) } else { glDisable(GL_BLEND) }
        // Restore depth mask
        glDepthMask(savedDepthMask)
        // Restore polygon offset
        if wasPolygonOffsetEnabled { glEnable(GL_POLYGON_OFFSET_FILL) } else { glDisable(GL_POLYGON_OFFSET_FILL) }
        // Restore alpha-to-coverage
        if wasAlphaToCoverageEnabled { glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE) } else { glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE) }
        // Restore depth test state
        if wasDepthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
        
      case .cutoutCoverage:
        // Restore blending state
        if wasBlendEnabled { glEnable(GL_BLEND) } else { glDisable(GL_BLEND) }
        // Restore depth mask
        glDepthMask(savedDepthMask)
        // Restore polygon offset
        if wasPolygonOffsetEnabled { glEnable(GL_POLYGON_OFFSET_FILL) } else { glDisable(GL_POLYGON_OFFSET_FILL) }
        // Restore alpha-to-coverage
        if wasAlphaToCoverageEnabled { glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE) } else { glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE) }
        // Restore depth test state
        if wasDepthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
        
      case .overlayBlend:
        // Restore blending state
        if wasBlendEnabled { glEnable(GL_BLEND) } else { glDisable(GL_BLEND) }
        // Restore depth mask
        glDepthMask(savedDepthMask)
        // Restore polygon offset
        if wasPolygonOffsetEnabled { glEnable(GL_POLYGON_OFFSET_FILL) } else { glDisable(GL_POLYGON_OFFSET_FILL) }
        // Restore alpha-to-coverage
        if wasAlphaToCoverageEnabled { glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE) } else { glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE) }
        // Restore depth test state
        if wasDepthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
        
      case .translucent:
        // Restore blending state
        if wasBlendEnabled { glEnable(GL_BLEND) } else { glDisable(GL_BLEND) }
        // Restore depth mask
        glDepthMask(savedDepthMask)
        // Restore polygon offset
        if wasPolygonOffsetEnabled { glEnable(GL_POLYGON_OFFSET_FILL) } else { glDisable(GL_POLYGON_OFFSET_FILL) }
        // Restore alpha-to-coverage
        if wasAlphaToCoverageEnabled { glEnable(GL_SAMPLE_ALPHA_TO_COVERAGE) } else { glDisable(GL_SAMPLE_ALPHA_TO_COVERAGE) }
        // Restore depth test state
        if wasDepthTestEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
      }
    } else if useFixedRenderState {
      if wasPolygonOffsetEnabled { glEnable(GL_POLYGON_OFFSET_FILL) } else { glDisable(GL_POLYGON_OFFSET_FILL) }
      if wasCullFaceEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
    }
    
    // Restore cull face state to what it was before we changed it
    if isDoubleSided {
      // We disabled culling, so restore it if it was enabled
      if wasCullFaceEnabled {
        glEnable(GL_CULL_FACE)
      }
    } else {
      // We enabled culling, so restore it if it was disabled
      if !wasCullFaceEnabled {
        glDisable(GL_CULL_FACE)
      }
    }
  }

  // MARK: - Async Texture Loading
  
  /// Alpha profile computed from texture alpha channel distribution
  /// Used for automatic classification of BLEND materials
  struct AlphaProfile {
    let minA: Float
    let maxA: Float
    let pctOpaque: Float      // Percentage of pixels with alpha > 0.98
    let pctTransparent: Float // Percentage of pixels with alpha < 0.02
    let pctMid: Float         // Percentage of pixels with 0.02 <= alpha <= 0.98
  }
  
  /// Compute alpha profile by sampling alpha channel sparsely (every 8th pixel)
  /// Returns profile with minA, maxA, and percentage distributions
  private nonisolated func computeAlphaProfile(_ image: ImageFormats.Image<ImageFormats.RGBA>) -> AlphaProfile {
    let bytes = image.bytes
    let pixelCount = image.width * image.height
    guard pixelCount > 0 else {
      return AlphaProfile(minA: 1.0, maxA: 1.0, pctOpaque: 1.0, pctTransparent: 0.0, pctMid: 0.0)
    }
    
    // Sample every 8th pixel for performance (or every pixel if small texture)
    let sampleStride = max(1, min(8, pixelCount / 1000))
    var minAlpha: Float = 1.0
    var maxAlpha: Float = 0.0
    var opaqueCount: Int = 0
    var transparentCount: Int = 0
    var midCount: Int = 0
    var totalSamples: Int = 0
    
    for i in stride(from: 0, to: pixelCount, by: sampleStride) {
      let alphaIndex = i * 4 + 3
      if alphaIndex < bytes.count {
        let alphaByte = bytes[alphaIndex]
        let alpha = Float(alphaByte) / 255.0
        minAlpha = min(minAlpha, alpha)
        maxAlpha = max(maxAlpha, alpha)
        totalSamples += 1
        
        if alpha > 0.98 {
          opaqueCount += 1
        } else if alpha < 0.02 {
          transparentCount += 1
        } else {
          midCount += 1
        }
      }
    }
    
    let total = Float(totalSamples)
    return AlphaProfile(
      minA: minAlpha,
      maxA: maxAlpha,
      pctOpaque: total > 0 ? Float(opaqueCount) / total : 1.0,
      pctTransparent: total > 0 ? Float(transparentCount) / total : 0.0,
      pctMid: total > 0 ? Float(midCount) / total : 0.0
    )
  }
  
  /// Scan texture alpha channel to determine if it has non-opaque pixels
  /// Returns true if minAlpha < 0.999 (has meaningful transparency)
  /// DEPRECATED: Use computeAlphaProfile instead for more detailed analysis
  private nonisolated func scanTextureAlpha(_ image: ImageFormats.Image<ImageFormats.RGBA>) -> Bool {
    let bytes = image.bytes
    let pixelCount = image.width * image.height
    guard pixelCount > 0 else { return false }
    
    // Sample alpha channel (every 4th byte, starting at index 3)
    // Use stride sampling for performance (sample every Nth pixel)
    let sampleStride = max(1, pixelCount / 1000)  // Sample up to 1000 pixels
    var minAlpha: Float = 1.0
    
    for i in stride(from: 0, to: pixelCount, by: sampleStride) {
      let alphaIndex = i * 4 + 3
      if alphaIndex < bytes.count {
        let alphaByte = bytes[alphaIndex]
        let alpha = Float(alphaByte) / 255.0
        minAlpha = min(minAlpha, alpha)
        
        // Early exit if we find non-opaque alpha
        if minAlpha < 0.999 {
          return true
        }
      }
    }
    
    return minAlpha < 0.999
  }
  
  /// Decode an image on a background thread (CPU-intensive work)
  private nonisolated func decodeImage(data: [UInt8], formatHint: String, displayPath: String, formattedBytes: String) async throws -> DecodedImage {
    let isPNG = formatHint.contains("png")
    let isWebP = formatHint.contains("webp")
    let isJPEG = formatHint.contains("jpg") || formatHint.contains("jpeg")
    
    // Decode on background thread
    if isPNG {
      let image = try logger.measure("\(formattedBytes) decoded \(displayPath)", level: .debug) {
        try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: data) { _ in }
      }
      return .rgba(image: image)
    } else if isWebP {
      let image = try logger.measure("\(formattedBytes) decoded \(displayPath)", level: .debug) {
        try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: data)
      }
      return .rgba(image: image)
    } else if isJPEG {
      let image = try logger.measure("\(formattedBytes) decoded \(displayPath)", level: .debug) {
        try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: data)
      }
      return .rgb(image: image)
    } else {
      // Try generic loader
      let image = try logger.measure("\(formattedBytes) decoded \(displayPath)", level: .debug) {
        try ImageFormats.Image<ImageFormats.RGBA>.load(from: data)
      }
      return .rgba(image: image)
    }
  }
  
  /// Upload decoded image to GPU on main thread (OpenGL requirement)
  private func uploadToGPU(
    decodedImage: DecodedImage, displayPath: String, formattedBytes: String,
    wrapS: GLTFWrapMode, wrapT: GLTFWrapMode,
    flipY: Bool, isSRGB: Bool, minFilter: GLint, mipmapped: Bool
  ) -> GLuint {
    // Lock to prevent concurrent OpenGL texture uploads from stomping on each other's state
    textureUploadLock.lock()
    defer { textureUploadLock.unlock() }
    
    // Clear any previous OpenGL errors (errors are sticky!)
    while glGetError() != GL_NO_ERROR {}
    
    var textureID: GLuint = 0
    glGenTextures(1, &textureID)
    
    if glGetError() != GL_NO_ERROR {
      logger.error("OpenGL error after glGenTextures for \(displayPath)")
      return 0
    }
    
    glBindTexture(GL_TEXTURE_2D, textureID)
    
    if glGetError() != GL_NO_ERROR {
      logger.error("OpenGL error after glBindTexture for \(displayPath)")
      glDeleteTextures(1, &textureID)
      return 0
    }
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    
    if glGetError() != GL_NO_ERROR {
      logger.error("OpenGL error after glTexParameteri for \(displayPath)")
      glDeleteTextures(1, &textureID)
      return 0
    }
    
    // Upload to GPU
    switch decodedImage {
    case .rgba(let image):
      let bytesToUpload: [UInt8]
      if flipY {
        bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
      } else {
        bytesToUpload = image.bytes
      }
      bytesToUpload.withUnsafeBytes { bytes in
        logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGBA,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      }
    case .rgb(let image):
      let bytesToUpload: [UInt8]
      if flipY {
        bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 3)
      } else {
        bytesToUpload = image.bytes
      }
      bytesToUpload.withUnsafeBytes { bytes in
        logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
          glTexImage2D(
            GL_TEXTURE_2D, 0, GL_RGB,
            GLsizei(image.width), GLsizei(image.height),
            0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
        }
      }
    }
    
    // Check for OpenGL errors after upload
    let error = glGetError()
    if error != GL_NO_ERROR {
      logger.error("OpenGL error after glTexImage2D for \(displayPath): \(error)")
      glDeleteTextures(1, &textureID)
      return 0
    }
    
    glBindTexture(GL_TEXTURE_2D, 0)
    return textureID
  }
  
  /// Load a single texture asynchronously (decode on background, upload on main thread)
  /// Returns (textureID, hasTexture, hasNonOpaqueAlpha, alphaProfile) tuple
  /// hasNonOpaqueAlpha is true if the texture has alpha < 0.999 (only for RGBA textures)
  /// alphaProfile contains detailed alpha distribution for automatic classification
  private func loadTextureAsync(
    path: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    context: String
  ) async
    -> (GLuint, Bool, Bool, AlphaProfile?)
  {
    // Create stable cache key
    let cacheKey = textureCacheKey(
      path: path, wrapS: wrapS, wrapT: wrapT, flipY: flipY, isSRGB: isSRGB, minFilter: minFilter,
      mipmapped: mipmapped
    )
    
    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.trace("Using cached texture for key \(cacheKey)")
      // For cached textures, we can't scan alpha, so assume opaque (conservative)
      return (cachedTexture, true, false, nil)
    }
    
    // Check if already loading
    if let inflightTask = TextureCache.shared.getInflightLoad(for: cacheKey) {
      logger.trace("Waiting for in-flight texture load: \(cacheKey)")
      do {
        let (textureID, _, _) = try await inflightTask.value
        // For in-flight textures, we can't scan alpha, so assume opaque (conservative)
        return (textureID, true, false, nil)
      } catch {
        logger.error("In-flight texture load failed for \(cacheKey): \(error)")
        return (0, false, false, nil)
      }
    }
    
    // Start new load
    let loadTask = Task<(GLuint, Bool, AlphaProfile?), Error> {
      // Get texture data
      let (data, formatHint, displayPath, formattedBytes): ([UInt8], String, String, String)
      
      if path.hasPrefix("*") {
        // Embedded texture
        guard let textureIndex = Int(String(path.dropFirst())),
              textureIndex < sceneData.embeddedTextures.count else {
          throw TextureLoadError.invalidPath(path)
        }
        
        let embeddedTexture = sceneData.embeddedTextures[textureIndex]
        let hint = embeddedTexture.formatHint?.lowercased() ?? ""
        let fileExt: String
        if hint.contains("png") {
          fileExt = "png"
        } else if hint.contains("webp") {
          fileExt = "webp"
        } else if hint.contains("jpg") || hint.contains("jpeg") {
          fileExt = "jpg"
        } else {
          fileExt = "unknown"
        }
        
        let display: String
        if let identifier = embeddedTexture.identifier {
          display = "\(bundleRelativeScenePath)/\(identifier).\(fileExt)\(context)"
        } else {
          display = "\(bundleRelativeScenePath)\(path)\(context)"
        }
        
        data = Array(embeddedTexture.data)
        formatHint = hint
        displayPath = display
        formattedBytes = embeddedTexture.data.count.formatBytes()
      } else {
        // External texture
        let sceneURL = URL(fileURLWithPath: sceneIdentifier)
        let sceneDirectory = sceneURL.deletingLastPathComponent()
        let textureURL = sceneDirectory.appendingPathComponent(path)
        
        // Try to load from resolved path or bundle
        var textureData: Data?
        if let loadedData = try? Data(contentsOf: textureURL) {
          textureData = loadedData
        } else {
          // Try bundle
          let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
          let pathExtension = URL(fileURLWithPath: cleanPath).pathExtension
          let pathWithoutExtension = URL(fileURLWithPath: cleanPath).deletingPathExtension().lastPathComponent
          if let bundlePath = Bundle.game.path(forResource: cleanPath, ofType: nil)
              ?? (pathExtension.isEmpty ? nil : Bundle.game.path(forResource: pathWithoutExtension, ofType: pathExtension)) {
            textureData = try? Data(contentsOf: URL(fileURLWithPath: bundlePath))
          }
        }
        
        guard let textureData else {
          throw TextureLoadError.fileNotFound(path)
        }
        
        data = Array(textureData)
        formatHint = URL(fileURLWithPath: path).pathExtension.lowercased()
        displayPath = "\(bundleRelativeScenePath)\(path)\(context)"
        formattedBytes = textureData.count.formatBytes()
      }
      
      logger.trace("loading \(formattedBytes) \(displayPath)")
      
      // Decode on background thread
      let decodedImage = try await decodeImage(data: data, formatHint: formatHint, displayPath: displayPath, formattedBytes: formattedBytes)
      
      // Compute alpha profile for automatic classification (only for RGBA images)
      let hasNonOpaqueAlpha: Bool
      let alphaProfile: AlphaProfile?
      if case .rgba(let image) = decodedImage {
        let profile = computeAlphaProfile(image)
        alphaProfile = profile
        hasNonOpaqueAlpha = profile.minA < 0.999
        if hasNonOpaqueAlpha {
          logger.trace("Texture '\(displayPath)' alpha profile: minA=\(profile.minA), maxA=\(profile.maxA), opaque=\(profile.pctOpaque*100)%, transparent=\(profile.pctTransparent*100)%, mid=\(profile.pctMid*100)%")
        }
      } else {
        // RGB images (JPEG) have no alpha channel, so always opaque
        hasNonOpaqueAlpha = false
        alphaProfile = nil
      }
      
      // Upload to GPU on main thread (explicitly hop to MainActor)
      let uploadedTextureID = await MainActor.run {
        uploadToGPU(
          decodedImage: decodedImage, displayPath: displayPath, formattedBytes: formattedBytes,
          wrapS: wrapS, wrapT: wrapT, flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped
        )
      }
      
      guard uploadedTextureID != 0 else {
        throw TextureLoadError.uploadFailed
      }
      
      // Cache the result
      TextureCache.shared.cacheTexture(uploadedTextureID, for: cacheKey)
      TextureCache.shared.removeInflightLoad(for: cacheKey)
      
      return (uploadedTextureID, hasNonOpaqueAlpha, alphaProfile)
    }
    
    // Register in-flight load
    TextureCache.shared.registerInflightLoad(loadTask, for: cacheKey)
    
    // Wait for result
    do {
      let (loadedTextureID, hasNonOpaqueAlpha, alphaProfile) = try await loadTask.value
      return (loadedTextureID, true, hasNonOpaqueAlpha, alphaProfile)
    } catch {
      logger.error("Failed to load texture \(path): \(error)")
      TextureCache.shared.removeInflightLoad(for: cacheKey)
      return (0, false, false, nil)
    }
  }
  
  /// Load all textures for this mesh instance (async version)
  func loadTextures() async {
    // Get material for this mesh
    guard let material else { return }

    // Load material properties
    loadMaterialProperties(material: material)

    let context = getTextureContext(material: material)

    // Load all PBR texture types
    if let info = material.diffuseTexture {
      let effectiveWrapS: GLTFWrapMode = info.path == "*1" ? .clamp_to_edge : info.wrapS
      let effectiveWrapT: GLTFWrapMode = info.path == "*1" ? .clamp_to_edge : info.wrapT
      let (textureID, hasTexture, hasNonOpaqueAlpha, alphaProfile) = await loadTextureAsync(
        path: info.path, wrapS: effectiveWrapS, wrapT: effectiveWrapT,
        flipY: false, isSRGB: true, minFilter: GL_LINEAR, mipmapped: false,
        context: context
      )
      diffuseTexture = textureID
      hasDiffuseTexture = hasTexture
      // Store alpha analysis for BLEND participation logic
      self.hasNonOpaqueAlpha = hasNonOpaqueAlpha
      self.alphaProfile = alphaProfile
    } else {
      // No texture means no alpha channel, so always opaque
      self.hasNonOpaqueAlpha = false
      self.alphaProfile = nil
    }
    
    // Compute render mode from alpha profile (after all textures loaded)
    // This ensures renderMode is available for logging, pass routing, and GL state
    computeRenderMode()
    
    // Log render mode and alpha profile for debugging
    let renderModeString: String
    switch renderMode {
    case .opaque: renderModeString = "Opaque"
    case .cutoutCoverage: renderModeString = "CutoutCoverage"
    case .overlayBlend: renderModeString = "OverlayBlend"
    case .translucent: renderModeString = "Translucent"
    }
    let materialName = material.name ?? "<unnamed>"
    let alphaModeStr = alphaMode == .blend ? "BLEND" : (alphaMode == .mask ? "MASK" : "OPAQUE")
    if let profile = alphaProfile {
      logger.trace(
        "🎨 Material '\(materialName)': renderMode=\(renderModeString), alphaMode=\(alphaModeStr), alphaProfile(minA=\(profile.minA), pctOpaque=\(profile.pctOpaque*100)%, pctTransparent=\(profile.pctTransparent*100)%, pctMid=\(profile.pctMid*100)%), useAlphaHash=\(useAlphaHash), isOverlayBlend=\(renderMode == .overlayBlend)"
      )
    } else {
      logger.trace(
        "🎨 Material '\(materialName)': renderMode=\(renderModeString), alphaMode=\(alphaModeStr), noAlphaProfile, opacity=\(opacity), useAlphaHash=\(useAlphaHash), isOverlayBlend=\(renderMode == .overlayBlend)"
      )
    }
    if let info = material.normalTexture {
      let (textureID, hasTexture, _, _) = await loadTextureAsync(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        context: context
      )
      normalTexture = textureID
      hasNormalTexture = hasTexture
    }
    if let info = material.roughnessTexture {
      let (textureID, hasTexture, _, _) = await loadTextureAsync(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        context: context
      )
      roughnessTexture = textureID
      hasRoughnessTexture = hasTexture
    }
    if let info = material.metallicTexture {
      let (textureID, hasTexture, _, _) = await loadTextureAsync(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        context: context
      )
      metallicTexture = textureID
      hasMetallicTexture = hasTexture
    }
    if let info = material.aoTexture {
      let (textureID, hasTexture, _, _) = await loadTextureAsync(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        context: context
      )
      aoTexture = textureID
      hasAoTexture = hasTexture
    }
  }

  // MARK: - Synchronous Texture Loading (Legacy)
  
  private func loadTexture() {
    // Get material for this mesh
    guard let material = material else { return }

    // Load material properties
    loadMaterialProperties(material: material)

    let context = getTextureContext(material: material)

    // Load all PBR texture types
    if let info = material.diffuseTexture {
      let effectiveWrapS: GLTFWrapMode = info.path == "*1" ? .clamp_to_edge : info.wrapS
      let effectiveWrapT: GLTFWrapMode = info.path == "*1" ? .clamp_to_edge : info.wrapT
      loadTextureFromPath(
        path: info.path, wrapS: effectiveWrapS, wrapT: effectiveWrapT,
        flipY: false, isSRGB: true, minFilter: GL_LINEAR, mipmapped: false,
        textureID: &diffuseTexture, hasTexture: &hasDiffuseTexture, context: context
      )
    }
    if let info = material.normalTexture {
      loadTextureFromPath(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        textureID: &normalTexture, hasTexture: &hasNormalTexture, context: context
      )
    }
    if let info = material.roughnessTexture {
      loadTextureFromPath(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        textureID: &roughnessTexture, hasTexture: &hasRoughnessTexture, context: context
      )
    }
    if let info = material.metallicTexture {
      loadTextureFromPath(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        textureID: &metallicTexture, hasTexture: &hasMetallicTexture, context: context
      )
    }
    if let info = material.aoTexture {
      loadTextureFromPath(
        path: info.path, wrapS: info.wrapS, wrapT: info.wrapT,
        flipY: false, isSRGB: false, minFilter: GL_LINEAR, mipmapped: false,
        textureID: &aoTexture, hasTexture: &hasAoTexture, context: context
      )
    }
  }

  /// Compute render mode from alpha profile and material properties
  /// Called after texture loading to determine final rendering behavior
  /// Clean classification based on alpha profile (no name heuristics)
  private func computeRenderMode() {
    if alphaMode == .blend, let profile = alphaProfile {
      let maxExtent = meshMaxExtent()
      // Automatic classification based on alpha profile
      if profile.minA > 0.98 {
        // (1) Opaque: minA > 0.98
        renderMode = .opaque
        useAlphaHash = false
      } else {
        let dominance = profile.pctOpaque + profile.pctTransparent
        let isBimodal = profile.minA < 0.1 && profile.maxA > 0.9 && profile.pctMid < 0.02
        let hairLikeCoverage = profile.pctOpaque > 0.5 && profile.pctTransparent > 0.1
        let mixedCoverage = profile.pctOpaque > 0.3 && profile.pctTransparent > 0.2
        let isSmallDecal = maxExtent > 0 && maxExtent < 0.2
        if dominance > 0.98 || isBimodal || profile.pctMid <= 0.05 || hairLikeCoverage || mixedCoverage {
          // (2) CutoutCoverage: dominant opaque/transparent or bimodal alpha (hair cards/foliage)
          renderMode = .cutoutCoverage
          useAlphaHash = true  // Use alpha-to-coverage or dither for hair cards
        } else if profile.pctMid > 0.01 {
          // (3) OverlayBlend: pctMid > 1% for smooth decals (brows/lashes/makeup)
          renderMode = .overlayBlend
          useAlphaHash = false
        } else {
          // (4) CutoutCoverage: fallback for coverage
          renderMode = .cutoutCoverage
          useAlphaHash = true
        }

        if renderMode == .cutoutCoverage && isSmallDecal {
          renderMode = .overlayBlend
          useAlphaHash = false
        }
      }

    } else if alphaMode == .blend {
      // Fallback: if no profile but alphaMode == BLEND, check opacity
      // If opacity is effectively 1.0, treat as opaque (skin without texture alpha)
      if opacity >= 0.999 {
        renderMode = .opaque
        useAlphaHash = false
      } else {
        // Otherwise default to overlayBlend (smooth blending)
        renderMode = .overlayBlend
        useAlphaHash = false
      }
    } else if alphaMode == .mask {
      // MASK mode: use cutout-style rendering (discard in shader)
      renderMode = .cutoutCoverage
      useAlphaHash = false  // MASK uses alphaCutoff discard, not dither
    } else {
      // OPAQUE mode
      renderMode = .opaque
      useAlphaHash = false
    }
  }

  private func meshMaxExtent() -> Float {
    guard !mesh.positions.isEmpty else { return 0 }
    var minX: Float = Float.infinity
    var minY: Float = Float.infinity
    var minZ: Float = Float.infinity
    var maxX: Float = -Float.infinity
    var maxY: Float = -Float.infinity
    var maxZ: Float = -Float.infinity

    let count = mesh.positions.count / 3
    for i in 0..<count {
      let x = mesh.positions[i * 3 + 0]
      let y = mesh.positions[i * 3 + 1]
      let z = mesh.positions[i * 3 + 2]
      minX = min(minX, x)
      minY = min(minY, y)
      minZ = min(minZ, z)
      maxX = max(maxX, x)
      maxY = max(maxY, y)
      maxZ = max(maxZ, z)
    }

    let extentX = maxX - minX
    let extentY = maxY - minY
    let extentZ = maxZ - minZ
    return max(extentX, max(extentY, extentZ))
  }
  
  private func loadMaterialProperties(material: Material) {
    // Store material name for debugging only (not used for rendering decisions)
    self.materialName = material.name
    baseColor = material.baseColor
    metallic = material.metallic
    roughness = material.roughness
    emissive = material.emissive
    opacity = material.opacity
    alphaMode = material.alphaMode
    alphaCutoff = material.alphaCutoff
    isDoubleSided = material.isDoubleSided
    depthBiasRole = material.depthBiasRole  // Explicit depth bias role
  }

  private func renderModeLabel(_ mode: RenderMode) -> String {
    switch mode {
    case .opaque:
      return "Opaque"
    case .cutoutCoverage:
      return "CutoutCoverage"
    case .overlayBlend:
      return "OverlayBlend"
    case .translucent:
      return "Translucent"
    }
  }

  private func glWrap(_ wrap: GLTFWrapMode) -> GLint {
    return GLint(wrap.rawValue)
  }

  private func flippedImageBytes(_ bytes: [UInt8], width: Int, height: Int, channels: Int) -> [UInt8] {
    let rowBytes = width * channels
    guard rowBytes > 0 else { return bytes }
    var flipped = [UInt8](repeating: 0, count: bytes.count)
    for y in 0..<height {
      let srcStart = y * rowBytes
      let dstStart = (height - 1 - y) * rowBytes
      flipped[dstStart..<dstStart + rowBytes] = bytes[srcStart..<srcStart + rowBytes]
    }
    return flipped
  }

  private func textureCacheKey(
    path: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool
  ) -> String {
    let wrapKey = "#wrapS=\(wrapS.rawValue),wrapT=\(wrapT.rawValue)"
    let stateKey = "#flipY=\(flipY),srgb=\(isSRGB),minFilter=\(minFilter),mip=\(mipmapped)"
    return path.hasPrefix("*") ? "\(sceneIdentifier)#\(path)\(wrapKey)\(stateKey)" : "\(path)\(wrapKey)\(stateKey)"
  }

  private func logUVBoundsIfNeeded() {
    guard !didLogUVBounds else { return }
    didLogUVBounds = true

    func uvBoundsLabel(_ label: String, uvs: [Float]?) -> String {
      guard let uvs, !uvs.isEmpty else {
        return "\(label)=missing"
      }
      var minU: Float = Float.infinity
      var minV: Float = Float.infinity
      var maxU: Float = -Float.infinity
      var maxV: Float = -Float.infinity
      let pairCount = uvs.count / 2
      for i in 0..<pairCount {
        let u = uvs[i * 2 + 0]
        let v = uvs[i * 2 + 1]
        minU = min(minU, u)
        minV = min(minV, v)
        maxU = max(maxU, u)
        maxV = max(maxV, v)
      }
      return "\(label)=min(\(minU), \(minV)) max(\(maxU), \(maxV))"
    }

    let name = mesh.name ?? "<unnamed>"
    let uv0Label = uvBoundsLabel("UV0", uvs: mesh.uvs)
    let uv1Label = uvBoundsLabel("UV1", uvs: mesh.uvs1)
    logger.trace("🧭 Mesh '\(name)' UV bounds: \(uv0Label), \(uv1Label)")

  }

  private func logDrawIfNeeded(passName: String, effectiveRenderMode: RenderMode) {
    let pass = passName.isEmpty ? "UnknownPass" : passName
    if pass == lastLoggedRenderPass && effectiveRenderMode == lastLoggedRenderMode {
      return
    }

    lastLoggedRenderPass = pass
    lastLoggedRenderMode = effectiveRenderMode

    let name = material?.name ?? materialName ?? "<unnamed>"
    let renderModeString = renderModeLabel(effectiveRenderMode)
    if let profile = alphaProfile {
      logger.trace(
        "🧾 Draw material '\(name)': pass=\(pass), renderMode=\(renderModeString), alphaProfile(minA=\(profile.minA), pctOpaque=\(profile.pctOpaque * 100)%, pctTransparent=\(profile.pctTransparent * 100)%, pctMid=\(profile.pctMid * 100)%)"
      )
    } else {
      logger.trace(
        "🧾 Draw material '\(name)': pass=\(pass), renderMode=\(renderModeString), alphaProfile=none"
      )
    }
  }

  private func loadTextureFromPath(
    path: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    textureID: inout GLuint,
    hasTexture: inout Bool,
    context: String
  ) {
    // Create stable cache key across loads for embedded textures by using scene file path
    let cacheKey = textureCacheKey(
      path: path, wrapS: wrapS, wrapT: wrapT, flipY: flipY, isSRGB: isSRGB, minFilter: minFilter,
      mipmapped: mipmapped
    )

    // Check cache first
    if let cachedTexture = TextureCache.shared.getCachedTexture(for: cacheKey) {
      logger.trace("Using cached texture for key \(cacheKey)")
      textureID = cachedTexture
      hasTexture = true
      return
    }

    // Check if it's an embedded texture (starts with "*")
    if path.hasPrefix("*") {
      loadEmbeddedTexture(
        texturePath: path, cacheKey: cacheKey, wrapS: wrapS, wrapT: wrapT,
        flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped,
        textureID: &textureID, hasTexture: &hasTexture, context: context
      )
    } else {
      logger.trace("Loading external texture: \(path)")
      loadExternalTexture(
        texturePath: path, wrapS: wrapS, wrapT: wrapT,
        flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped,
        textureID: &textureID, hasTexture: &hasTexture, context: context
      )
    }
  }

  private func loadEmbeddedTexture(
    texturePath: String,
    cacheKey: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    textureID: inout GLuint,
    hasTexture: inout Bool,
    context: String
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
      logger.warning(
        "Embedded texture index \(textureIndex) out of bounds (total: \(sceneData.embeddedTextures.count))")
      return
    }

    logger.trace(
      "Loading embedded texture [\(textureIndex)]: path=\(texturePath), total embedded textures=\(sceneData.embeddedTextures.count)"
    )
    let embeddedTexture = sceneData.embeddedTextures[textureIndex]
    logger.trace(
      "Embedded texture [\(textureIndex)]: data size=\(embeddedTexture.data.count) bytes, formatHint=\(embeddedTexture.formatHint ?? "nil")"
    )
    createOpenGLTexture(
      from: embeddedTexture, texturePath: texturePath, cacheKey: cacheKey, wrapS: wrapS, wrapT: wrapT,
      flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped,
      textureID: &textureID,
      hasTexture: &hasTexture, context: context)
  }

  private func loadExternalTexture(
    texturePath: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    textureID: inout GLuint,
    hasTexture: inout Bool,
    context: String
  ) {
    // Create cache key for external textures
    let cacheKey = textureCacheKey(
      path: texturePath, wrapS: wrapS, wrapT: wrapT, flipY: flipY, isSRGB: isSRGB, minFilter: minFilter,
      mipmapped: mipmapped
    )

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
      loadTextureFromData(
        textureData, texturePath: texturePath, cacheKey: cacheKey, wrapS: wrapS, wrapT: wrapT,
        flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped,
        textureID: &textureID, hasTexture: &hasTexture, context: context)
      return
    }

    // If that fails, try loading from Bundle.game (for textures in the bundle)
    // Remove any leading path separators and directory components
    let cleanPath = texturePath.hasPrefix("/") ? String(texturePath.dropFirst()) : texturePath
    let pathExtension = URL(fileURLWithPath: cleanPath).pathExtension
    let pathWithoutExtension = URL(fileURLWithPath: cleanPath).deletingPathExtension().lastPathComponent
    if let bundlePath = Bundle.game.path(forResource: cleanPath, ofType: nil)
      ?? (pathExtension.isEmpty ? nil : Bundle.game.path(forResource: pathWithoutExtension, ofType: pathExtension))
    {
      let bundleURL = URL(fileURLWithPath: bundlePath)
      if let textureData = try? Data(contentsOf: bundleURL) {
        loadTextureFromData(
          textureData, texturePath: texturePath, cacheKey: cacheKey, wrapS: wrapS, wrapT: wrapT,
          flipY: flipY, isSRGB: isSRGB, minFilter: minFilter, mipmapped: mipmapped,
          textureID: &textureID, hasTexture: &hasTexture, context: context)
        return
      }
    }

    logger.warning("Failed to load external texture: \(texturePath) (tried: \(textureURL.path))")
  }

  private func loadTextureFromData(
    _ data: Data,
    texturePath: String,
    cacheKey: String,
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    textureID: inout GLuint,
    hasTexture: inout Bool,
    context: String
  ) {
    // Create a temporary EmbeddedTexture-like structure
    let dataArray = Array(data)
    let formatHint = URL(fileURLWithPath: texturePath).pathExtension.lowercased()

    // Determine format from file extension
    let isPNG = formatHint == "png"
    let isWebP = formatHint == "webp"
    let isJPEG = formatHint == "jpg" || formatHint == "jpeg"

    let displayPath = "\(bundleRelativeScenePath)\(texturePath)\(context)"
    let formattedBytes = data.count.formatBytes()
    logger.trace("loading \(formattedBytes) \(displayPath)")

    do {
      if isPNG {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: dataArray) { _ in }
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
          hasTexture = true
        }
      } else if isWebP {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
          hasTexture = true
        }
      } else if isJPEG {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 3)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGB,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
          hasTexture = true
        }
      } else {
        // Try generic loader
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.load(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          glGenTextures(1, &textureID)
          glBindTexture(GL_TEXTURE_2D, textureID)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
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
    wrapS: GLTFWrapMode,
    wrapT: GLTFWrapMode,
    flipY: Bool,
    isSRGB: Bool,
    minFilter: GLint,
    mipmapped: Bool,
    textureID: inout GLuint,
    hasTexture: inout Bool,
    context: String
  ) {
    glGenTextures(1, &textureID)
    glBindTexture(GL_TEXTURE_2D, textureID)

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, glWrap(wrapS))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, glWrap(wrapT))
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

    let data = embeddedTexture.data
    let dataArray = Array(data)
    let formatHint = embeddedTexture.formatHint?.lowercased() ?? ""
    
    // Determine file extension from hint
    let fileExtension: String
    if formatHint.contains("png") {
      fileExtension = "png"
    } else if formatHint.contains("webp") {
      fileExtension = "webp"
    } else if formatHint.contains("jpg") || formatHint.contains("jpeg") {
      fileExtension = "jpg"
    } else {
      fileExtension = "unknown"
    }

    // Build display path with identifier if available
    let displayPath: String
    if let identifier = embeddedTexture.identifier {
      displayPath = "\(bundleRelativeScenePath)/\(identifier).\(fileExtension)\(context)"
    } else {
      displayPath = "\(bundleRelativeScenePath)\(texturePath)\(context)"
    }
    
    let formattedBytes = data.count.formatBytes()
    logger.debug("loading \(formattedBytes) \(displayPath)")

    do {
      // Try to determine format from hint
      if formatHint.contains("png") {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.loadPNG(from: dataArray) { progress in
            logger.debug("Loading PNG texture: \(progress * 100)%")
          }
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        }
      } else if formatHint.contains("webp") {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.loadWebP(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        }
      } else if formatHint.contains("jpg") || formatHint.contains("jpeg") {
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGB>.loadJPEG(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 3)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGB,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGB, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
        }
      } else {
        // Try generic loader
        let image = try logger.measure("decoded \(formattedBytes) \(displayPath)", level: .debug) {
          try ImageFormats.Image<ImageFormats.RGBA>.load(from: dataArray)
        }
        let bytesToUpload: [UInt8]
        if flipY {
          bytesToUpload = flippedImageBytes(image.bytes, width: image.width, height: image.height, channels: 4)
        } else {
          bytesToUpload = image.bytes
        }
        bytesToUpload.withUnsafeBytes { bytes in
          logger.measure("\(formattedBytes) uploaded \(displayPath)", level: .debug) {
            glTexImage2D(
              GL_TEXTURE_2D, 0, GL_RGBA,
              GLsizei(image.width), GLsizei(image.height),
              0, GL_RGBA, GL_UNSIGNED_BYTE, bytes.baseAddress)
          }
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
    logger.trace("Cached texture for key \(cacheKey), textureID=\(textureID), hasTexture=\(hasTexture)")
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
      let t1: (Float, Float)
      if let uvs1 = uvs1, uvs1.count >= (i * 2 + 2) {
        t1 = (uvs1[i * 2 + 0], uvs1[i * 2 + 1])
      } else {
        t1 = (0, 0)
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
        uv1: t1,
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
    (Int32, Int32, Int32, Int32), (Float, Float, Float, Float)
  ) {
    guard let vertexWeights = boneWeightMap[vertexIndex], !vertexWeights.isEmpty else {
      // No bone weights for this vertex - return -1 for indices (like LearnOpenGL uses -1 for unused)
      return ((-1, -1, -1, -1), (0, 0, 0, 0))
    }

    // Sort weights by weight value (descending) and take up to 4
    let sortedWeights = vertexWeights.sorted { $0.weight > $1.weight }.prefix(4)

    var indices: (Int32, Int32, Int32, Int32) = (-1, -1, -1, -1)  // -1 means unused (like LearnOpenGL)
    var weights: (Float, Float, Float, Float) = (0, 0, 0, 0)

    for (i, weightData) in sortedWeights.enumerated() {
      switch i {
      case 0:
        indices.0 = Int32(weightData.boneIndex)
        weights.0 = weightData.weight
      case 1:
        indices.1 = Int32(weightData.boneIndex)
        weights.1 = weightData.weight
      case 2:
        indices.2 = Int32(weightData.boneIndex)
        weights.2 = weightData.weight
      case 3:
        indices.3 = Int32(weightData.boneIndex)
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

// MARK: - Async Loading Helpers

extension Collection where Element == MeshInstance {
  /// Load textures for all mesh instances concurrently with a concurrency limit
  /// - Parameter maxConcurrent: Maximum number of textures to decode simultaneously (default: 3)
  func loadTexturesConcurrently(maxConcurrent: Int = 3) async {
    guard !isEmpty else { return }
    
    let instances = Array(self)
    await withTaskGroup(of: Void.self) { group in
      var activeLoads = 0
      var nextIndex = 0
      
      while nextIndex < instances.count || activeLoads > 0 {
        // Start new tasks if we're below the limit
        while activeLoads < maxConcurrent && nextIndex < instances.count {
          let meshInstance = instances[nextIndex]
          
          group.addTask {
            await meshInstance.loadTextures()
          }
          
          activeLoads += 1
          nextIndex += 1
        }
        
        // Wait for one task to complete
        if let _ = await group.next() {
          activeLoads -= 1
        }
      }
    }
  }
}
