import Assimp

extension Mesh {
  /// Initialize from an Assimp Mesh
  public init(_ assimpMesh: Assimp.Mesh) {
    self.name = assimpMesh.name
    self.numberOfVertices = assimpMesh.numberOfVertices
    self.numberOfFaces = assimpMesh.numberOfFaces
    self.numberOfBones = assimpMesh.numberOfBones
    self.materialIndex = assimpMesh.materialIndex
    
    // Convert positions
    let assimpPositions = assimpMesh.vertices
    var positionsArray: [Float] = []
    positionsArray.reserveCapacity(numberOfVertices * 3)
    for i in 0..<numberOfVertices {
      positionsArray.append(Float(assimpPositions[i * 3 + 0]))
      positionsArray.append(Float(assimpPositions[i * 3 + 1]))
      positionsArray.append(Float(assimpPositions[i * 3 + 2]))
    }
    self.positions = positionsArray
    
    // Convert normals
    let assimpNormals = assimpMesh.normals
    if !assimpNormals.isEmpty && assimpNormals.count >= numberOfVertices * 3 {
      var normalsArray: [Float] = []
      normalsArray.reserveCapacity(numberOfVertices * 3)
      for i in 0..<numberOfVertices {
        normalsArray.append(Float(assimpNormals[i * 3 + 0]))
        normalsArray.append(Float(assimpNormals[i * 3 + 1]))
        normalsArray.append(Float(assimpNormals[i * 3 + 2]))
      }
      self.normals = normalsArray
    } else {
      self.normals = nil
    }
    
    // Convert UVs (first channel)
    if let uvs = assimpMesh.texCoordsPacked.0, !uvs.isEmpty && uvs.count >= numberOfVertices * 2 {
      self.uvs = (0..<numberOfVertices).flatMap { i in
        [Float(uvs[i * 2 + 0]), Float(uvs[i * 2 + 1])]
      }
    } else {
      self.uvs = nil
    }
    
    // Convert tangents
    let assimpTangents = assimpMesh.tangents
    if !assimpTangents.isEmpty && assimpTangents.count >= numberOfVertices * 3 {
      var tangentsArray: [Float] = []
      tangentsArray.reserveCapacity(numberOfVertices * 3)
      for i in 0..<numberOfVertices {
        tangentsArray.append(Float(assimpTangents[i * 3 + 0]))
        tangentsArray.append(Float(assimpTangents[i * 3 + 1]))
        tangentsArray.append(Float(assimpTangents[i * 3 + 2]))
      }
      self.tangents = tangentsArray
    } else {
      self.tangents = nil
    }
    
    // Convert bitangents
    let assimpBitangents = assimpMesh.bitangents
    if !assimpBitangents.isEmpty && assimpBitangents.count >= numberOfVertices * 3 {
      var bitangentsArray: [Float] = []
      bitangentsArray.reserveCapacity(numberOfVertices * 3)
      for i in 0..<numberOfVertices {
        bitangentsArray.append(Float(assimpBitangents[i * 3 + 0]))
        bitangentsArray.append(Float(assimpBitangents[i * 3 + 1]))
        bitangentsArray.append(Float(assimpBitangents[i * 3 + 2]))
      }
      self.bitangents = bitangentsArray
    } else {
      self.bitangents = nil
    }
    
    // Convert faces
    self.faces = assimpMesh.faces.map { face in
      Face(indices: face.indices.map { Int($0) })
    }
    
    // Convert bones
    self.bones = assimpMesh.bones.map { assimpBone in
      Bone(
        name: assimpBone.name,
        offsetMatrix: assimpBone.offsetMatrix.mat4Representation,
        weights: assimpBone.weights.map { weight in
          VertexWeight(vertexIndex: weight.vertexIndex, weight: Float(weight.weight))
        }
      )
    }
  }
}

extension Material {
  /// Initialize from an Assimp Material
  public init(_ assimpMaterial: Assimp.Material, materialIndex: Int) {
    self.name = assimpMaterial.name
    self.materialIndex = materialIndex
    
    // Load base color (diffuse color)
    if let color = assimpMaterial.getMaterialColor(.COLOR_DIFFUSE) {
      self.baseColor = vec3(color.x, color.y, color.z)
    } else {
      self.baseColor = vec3(0.8, 0.8, 0.8)
    }
    
    // Load PBR properties
    if let metallicFactor = assimpMaterial.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_METALLIC_FACTOR)?.float.first {
      self.metallic = metallicFactor
    } else {
      self.metallic = 0.0
    }
    
    if let roughnessFactor = assimpMaterial.getMaterialProperty(.GLTF_PBRMETALLICROUGHNESS_ROUGHNESS_FACTOR)?.float.first {
      self.roughness = roughnessFactor
    } else {
      self.roughness = 0.5
    }
    
    // Load emissive color
    if let emissiveColor = assimpMaterial.getMaterialColor(.COLOR_EMISSIVE) {
      self.emissive = vec3(emissiveColor.x, emissiveColor.y, emissiveColor.z)
    } else {
      self.emissive = vec3(0, 0, 0)
    }
    
    // Load opacity
    if let opacityValue = assimpMaterial.getMaterialProperty(.OPACITY)?.float.first {
      self.opacity = opacityValue
    } else {
      self.opacity = 1.0
    }
    
    // Load texture paths
    self.diffuseTexturePath = assimpMaterial.getMaterialTexture(texType: .diffuse, texIndex: 0)
    self.normalTexturePath = assimpMaterial.getMaterialTexture(texType: .normals, texIndex: 0)
    self.roughnessTexturePath = assimpMaterial.getMaterialTexture(texType: .diffuseRoughness, texIndex: 0)
    self.metallicTexturePath = assimpMaterial.getMaterialTexture(texType: .metalness, texIndex: 0)
    self.aoTexturePath = assimpMaterial.getMaterialTexture(texType: .ambientOcclusion, texIndex: 0)
  }
}

extension Animation {
  /// Initialize from an Assimp Animation
  public init(_ assimpAnimation: Assimp.Animation) {
    self.name = assimpAnimation.name
    self.duration = assimpAnimation.duration
    self.ticksPerSecond = assimpAnimation.ticksPerSecond > 0 ? assimpAnimation.ticksPerSecond : 25.0
    
    self.channels = assimpAnimation.channels.map { assimpChannel in
      AnimationChannel(
        nodeName: assimpChannel.nodeName ?? "",
        positionKeys: assimpChannel.positionKeys.map { key in
          VectorKey(time: key.time, value: vec3(Float(key.value.x), Float(key.value.y), Float(key.value.z)))
        },
        rotationKeys: assimpChannel.rotationKeys.map { key in
          QuatKey(
            time: key.time,
            value: Quaternion<Float>(key.value.w, key.value.x, key.value.y, key.value.z)
          )
        },
        scalingKeys: assimpChannel.scalingKeys.map { key in
          VectorKey(time: key.time, value: vec3(Float(key.value.x), Float(key.value.y), Float(key.value.z)))
        }
      )
    }
  }
}

extension Scene {
  /// Initialize from an Assimp Scene
  public convenience init(_ assimpScene: Assimp.Scene, filePath: String) {
    // Convert meshes
    let meshes = assimpScene.meshes.map { Mesh($0) }
    
    // Convert materials
    let materials = assimpScene.materials.enumerated().map { index, material in
      Material(material, materialIndex: index)
    }
    
    // Convert animations
    let animations = assimpScene.animations.map { Animation($0) }
    
    // Convert embedded textures
    let embeddedTextures = assimpScene.textures.enumerated().map { index, texture in
        EmbeddedTexture(
          index: index,
          data: Data(texture.textureData),
          width: texture.width,
          height: texture.height,
          formatHint: texture.achFormatHint.isEmpty ? nil : texture.achFormatHint
        )
    }
    
    // Convert node hierarchy - use Node's convenience initializer from Assimp.Node
    let rootNode = Node(assimpScene.rootNode)
    
    // Call designated initializer
    self.init(
      filePath: filePath,
      rootNode: rootNode,
      meshes: meshes,
      materials: materials,
      cameras: [],  // Assimp scenes don't have cameras in our format yet
      animations: animations,
      embeddedTextures: embeddedTextures
    )
    
    // Store Assimp scene for backward compatibility
    self._assimpScene = assimpScene
  }
}

