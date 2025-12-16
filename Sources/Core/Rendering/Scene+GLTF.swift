import CGLTF
import GLTF
import GLMath

// Helper function to extract data from a GLTF accessor
// Uses cgltf's official unpack_floats function which handles all edge cases correctly
private func extractAccessorData(_ accessor: GLTFAccessor) -> [Float]? {
  // Use cgltf's official unpack_floats function - it handles:
  // - Sparse accessors
  // - Normalization
  // - Correct stride calculation
  // - Component type conversion
  // - Buffer view data pointer resolution
  // - All edge cases we were missing
  return accessor.unpackFloats()
}

// Helper function to extract indices from a GLTF accessor
// Use cgltf's official unpack_indices function as recommended by the readme
private func extractIndices(_ accessor: GLTFAccessor) -> [UInt32]? {
  guard accessor.type == .scalar else {
    logger.error("❌ extractIndices: Accessor type is \(accessor.type), expected .scalar for indices")
    return nil
  }
  return accessor.unpackIndices()
}

extension Mesh {
  /// Initialize from pre-extracted GLTF data (for two-pass loading)
  /// This allows all buffer data to be extracted first, then processed
  internal init(
    name: String?,
    positions: [Float],
    normals: [Float]?,
    uvs: [Float]?,
    tangents: [Float]?,
    indexData: [UInt32]?,
    vertexCount: Int,
    materialIndex: Int
  ) {
    var bitangents: [Float]?
    let finalVertexCount: Int

    // Validate positions
    let expectedPositionCount = vertexCount * 3
    if positions.count != expectedPositionCount {
      logger.error(
        "❌ Mesh '\(name ?? "<unnamed>")' position count mismatch: expected \(expectedPositionCount), got \(positions.count)"
      )
      let actualVertexCount = positions.count / 3
      if actualVertexCount > 0 {
        logger.warning("⚠️ Using actual vertex count: \(actualVertexCount)")
        finalVertexCount = actualVertexCount
      } else {
        logger.error("❌ Cannot recover: positions array is empty, creating empty mesh")
        self.init(
          name: name,
          numberOfVertices: 0,
          numberOfFaces: 0,
          numberOfBones: 0,
          materialIndex: materialIndex,
          positions: [],
          normals: nil,
          uvs: nil,
          tangents: nil,
          bitangents: nil,
          faces: [],
          bones: []
        )
        return
      }
    } else {
      finalVertexCount = vertexCount
    }

    // Convert indices to faces
    var faces: [Face] = []
    if let indexData = indexData {
      // Validate index data
      let maxIndexInData = indexData.max() ?? 0
      if maxIndexInData >= UInt32(finalVertexCount) {
        logger.error(
          "❌ Mesh '\(name ?? "<unnamed>")': Index data appears corrupted - max index is \(maxIndexInData) but vertexCount is only \(finalVertexCount)"
        )
      }

      // Convert to triangular faces
      for i in stride(from: 0, to: indexData.count, by: 3) {
        if i + 2 < indexData.count {
          let idx0 = Int(indexData[i])
          let idx1 = Int(indexData[i + 1])
          let idx2 = Int(indexData[i + 2])

          guard idx0 >= 0 && idx1 >= 0 && idx2 >= 0 else {
            logger.warning("⚠️ Negative vertex index in face: [\(idx0), \(idx1), \(idx2)]")
            continue
          }

          if idx0 > 100000 || idx1 > 100000 || idx2 > 100000 {
            logger.error("❌ Mesh '\(name ?? "<unnamed>")': Corrupted index detected: [\(idx0), \(idx1), \(idx2)]")
            continue
          }

          faces.append(Face(indices: [idx0, idx1, idx2]))
        }
      }
    } else {
      // No indices - assume sequential vertices
      for i in stride(from: 0, to: finalVertexCount, by: 3) {
        if i + 2 < finalVertexCount {
          faces.append(Face(indices: [i, i + 1, i + 2]))
        }
      }
    }

    // Validate and filter faces
    let validFaces = faces.filter { face in
      guard face.indices.count == 3 else { return false }
      let idx0 = face.indices[0]
      let idx1 = face.indices[1]
      let idx2 = face.indices[2]
      let isValid =
        idx0 >= 0 && idx0 < finalVertexCount && idx1 >= 0 && idx1 < finalVertexCount && idx2 >= 0
        && idx2 < finalVertexCount
      if !isValid {
        logger.warning(
          "⚠️ Invalid vertex index in face: [\(idx0), \(idx1), \(idx2)], finalVertexCount=\(finalVertexCount)")
      }
      return isValid
    }

    // Calculate tangent space if needed
    if tangents == nil, let normals = normals, let uvs = uvs, !validFaces.isEmpty {
      var tangentAccum: [vec3] = Array(repeating: vec3(0, 0, 0), count: finalVertexCount)
      var bitangentAccum: [vec3] = Array(repeating: vec3(0, 0, 0), count: finalVertexCount)

      for face in validFaces {
        guard face.indices.count == 3 else { continue }
        let i0 = face.indices[0]
        let i1 = face.indices[1]
        let i2 = face.indices[2]

        let v0 = vec3(positions[i0 * 3], positions[i0 * 3 + 1], positions[i0 * 3 + 2])
        let v1 = vec3(positions[i1 * 3], positions[i1 * 3 + 1], positions[i1 * 3 + 2])
        let v2 = vec3(positions[i2 * 3], positions[i2 * 3 + 1], positions[i2 * 3 + 2])

        let uv0 = vec2(uvs[i0 * 2], uvs[i0 * 2 + 1])
        let uv1 = vec2(uvs[i1 * 2], uvs[i1 * 2 + 1])
        let uv2 = vec2(uvs[i2 * 2], uvs[i2 * 2 + 1])

        let deltaPos1 = v1 - v0
        let deltaPos2 = v2 - v0
        let deltaUV1 = uv1 - uv0
        let deltaUV2 = uv2 - uv0

        let r = 1.0 / (deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x)
        let tangent = (deltaPos1 * deltaUV2.y - deltaPos2 * deltaUV1.y) * r
        let bitangent = (deltaPos2 * deltaUV1.x - deltaPos1 * deltaUV2.x) * r

        tangentAccum[i0] = tangentAccum[i0] + tangent
        tangentAccum[i1] = tangentAccum[i1] + tangent
        tangentAccum[i2] = tangentAccum[i2] + tangent
        bitangentAccum[i0] = bitangentAccum[i0] + bitangent
        bitangentAccum[i1] = bitangentAccum[i1] + bitangent
        bitangentAccum[i2] = bitangentAccum[i2] + bitangent
      }

      var tangentsArray: [Float] = []
      var bitangentsArray: [Float] = []
      tangentsArray.reserveCapacity(finalVertexCount * 3)
      bitangentsArray.reserveCapacity(finalVertexCount * 3)

      for i in 0..<finalVertexCount {
        let n = vec3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2])
        var t = normalize(tangentAccum[i])
        var b = normalize(bitangentAccum[i])

        t = normalize(t - dot(t, n) * n)
        b = cross(n, t)

        if dot(cross(n, t), b) < 0.0 {
          t = -t
        }

        tangentsArray.append(t.x)
        tangentsArray.append(t.y)
        tangentsArray.append(t.z)
        bitangentsArray.append(b.x)
        bitangentsArray.append(b.y)
        bitangentsArray.append(b.z)
      }

      // Update tangents (we can't reassign to the parameter, so we'll use a local var)
      let calculatedTangents = tangentsArray
      let calculatedBitangents = bitangentsArray

      self.init(
        name: name,
        numberOfVertices: finalVertexCount,
        numberOfFaces: validFaces.count,
        numberOfBones: 0,
        materialIndex: materialIndex,
        positions: positions,
        normals: normals,
        uvs: uvs,
        tangents: calculatedTangents,
        bitangents: calculatedBitangents,
        faces: validFaces,
        bones: []
      )
      return
    } else if let normals = normals, let tangents = tangents, normals.count == tangents.count {
      // Calculate bitangents from normals and tangents
      var bitangentsArray: [Float] = []
      bitangentsArray.reserveCapacity(normals.count)
      for i in stride(from: 0, to: normals.count, by: 3) {
        let n = vec3(normals[i], normals[i + 1], normals[i + 2])
        let t = vec3(tangents[i], tangents[i + 1], tangents[i + 2])
        let b = cross(n, t)
        bitangentsArray.append(b.x)
        bitangentsArray.append(b.y)
        bitangentsArray.append(b.z)
      }
      bitangents = bitangentsArray
    }

    self.init(
      name: name,
      numberOfVertices: finalVertexCount,
      numberOfFaces: validFaces.count,
      numberOfBones: 0,
      materialIndex: materialIndex,
      positions: positions,
      normals: normals,
      uvs: uvs,
      tangents: tangents,
      bitangents: bitangents,
      faces: validFaces,
      bones: []
    )
  }

  /// Initialize from a GLTF Mesh primitive
  /// Note: GLTF meshes can have multiple primitives, so we create one Mesh per primitive
  public init(_ gltfPrimitive: GLTFPrimitive, gltfMesh: GLTFMesh, materialIndex: Int) {
    // Extract vertex attributes
    var positions: [Float] = []
    var normals: [Float]?
    var uvs: [Float]?
    var tangents: [Float]?
    var bitangents: [Float]?
    var vertexCount = 0

    for attribute in gltfPrimitive.attributes {
      switch attribute.type {
      case .position:
        if let data = extractAccessorData(attribute.data) {
          positions = data
          // For vec3 positions, vertexCount should be positions.count / 3
          // But attribute.data.count is the accessor element count (number of vec3s)
          // So both should match - validate this
          let expectedVertexCount = data.count / 3
          let accessorCount = attribute.data.count
          if expectedVertexCount != accessorCount {
            logger.warning(
              "⚠️ Position count mismatch in mesh '\(gltfMesh.name)': positions.count/3=\(expectedVertexCount), accessor.count=\(accessorCount)"
            )
          }
          vertexCount = accessorCount  // Use accessor count as source of truth
        }
      case .normal:
        if let data = extractAccessorData(attribute.data) {
          normals = data
        }
      case .texcoord:
        if attribute.index == 0, let data = extractAccessorData(attribute.data) {
          // Only take first UV channel
          uvs = data
        }
      case .tangent:
        if let data = extractAccessorData(attribute.data) {
          tangents = data
        }
      default:
        break
      }
    }

    // Extract indices first (needed for tangent calculation)
    // Note: We'll validate indices against finalVertexCount after we determine it
    var faces: [Face] = []
    if let indices = gltfPrimitive.indices, let indexData = extractIndices(indices) {
      // Validate index data immediately - check for obviously corrupted values
      let maxIndexInData = indexData.max() ?? 0
      let minIndexInData = indexData.min() ?? 0

      // If we have vertexCount, validate indices are reasonable
      if vertexCount > 0 {
        if maxIndexInData >= UInt32(vertexCount) {
          // Log detailed accessor information to help diagnose corruption
          let accessor = indices
          let bufferView = accessor.bufferView
          let buffer = bufferView?.buffer
          logger.error(
            "❌ Mesh '\(gltfMesh.name)': Index data appears corrupted - max index is \(maxIndexInData) but vertexCount is only \(vertexCount). This suggests pointer corruption, wrong buffer, or wrong data type."
          )
          logger.error(
            "   Index range: [\(minIndexInData), \(maxIndexInData)], first 10 indices: \(Array(indexData.prefix(10)))")
          logger.error(
            "   Accessor details: componentType=\(accessor.componentType), type=\(accessor.type), count=\(accessor.count), offset=\(accessor.offset), stride=\(accessor.stride)"
          )
          if let bufferView = bufferView {
            logger.error(
              "   BufferView details: offset=\(bufferView.offset), size=\(bufferView.size), stride=\(bufferView.stride)"
            )
          }
          if let buffer = buffer {
            logger.error(
              "   Buffer details: size=\(buffer.size), hasDataPointer=\(buffer.dataPointer != nil)")
          }
          // Don't return nil - filter bad indices instead
        }
      } else if maxIndexInData > 100000 {
        // Log detailed accessor information to help diagnose corruption
        let accessor = indices
        let bufferView = accessor.bufferView
        let buffer = bufferView?.buffer
        logger.error(
          "❌ Mesh '\(gltfMesh.name)': Index data appears corrupted - max index is \(maxIndexInData) (absurdly large). This suggests pointer corruption or wrong data type."
        )
        logger.error("   First 10 indices: \(Array(indexData.prefix(10)))")
        logger.error(
          "   Accessor details: componentType=\(accessor.componentType), type=\(accessor.type), count=\(accessor.count), offset=\(accessor.offset), stride=\(accessor.stride)"
        )
        if let bufferView = bufferView {
          logger.error(
            "   BufferView details: offset=\(bufferView.offset), size=\(bufferView.size), stride=\(bufferView.stride)")
        }
        if let buffer = buffer {
          logger.error(
            "   Buffer details: size=\(buffer.size), hasDataPointer=\(buffer.dataPointer != nil)")
        }
      }

      // Convert to triangular faces
      for i in stride(from: 0, to: indexData.count, by: 3) {
        if i + 2 < indexData.count {
          let idx0 = Int(indexData[i])
          let idx1 = Int(indexData[i + 1])
          let idx2 = Int(indexData[i + 2])

          // Validate indices are non-negative (will validate against final vertex count later)
          guard idx0 >= 0 && idx1 >= 0 && idx2 >= 0 else {
            logger.warning(
              "⚠️ Negative vertex index in face: indices=[\(idx0), \(idx1), \(idx2)], mesh='\(gltfMesh.name)'")
            continue
          }

          // Early check for obviously corrupted indices (before we know finalVertexCount)
          // If we have vertexCount, use it; otherwise just check for absurdly large values
          if idx0 > 100000 || idx1 > 100000 || idx2 > 100000 {
            logger.error(
              "❌ Mesh '\(gltfMesh.name)': Corrupted index detected at face \(i/3): [\(idx0), \(idx1), \(idx2)]. Skipping face."
            )
            continue
          }

          faces.append(
            Face(indices: [idx0, idx1, idx2])
          )
        }
      }
    } else {
      // No indices - assume sequential vertices
      for i in stride(from: 0, to: vertexCount, by: 3) {
        if i + 2 < vertexCount {
          faces.append(Face(indices: [i, i + 1, i + 2]))
        }
      }
    }

    // Validate that positions array size matches vertexCount
    let expectedPositionCount = vertexCount * 3
    let finalVertexCount: Int
    if positions.count != expectedPositionCount {
      logger.error(
        "❌ Mesh '\(gltfMesh.name)' position count mismatch: expected \(expectedPositionCount) (vertexCount=\(vertexCount) * 3), got \(positions.count)"
      )
      // Try to recover by using actual position count
      let actualVertexCount = positions.count / 3
      if actualVertexCount > 0 {
        logger.warning("⚠️ Using actual vertex count: \(actualVertexCount)")
        finalVertexCount = actualVertexCount
      } else {
        logger.error("❌ Cannot recover: positions array is empty or invalid, creating empty mesh")
        // Create empty mesh to prevent crashes
        self.init(
          name: gltfMesh.name.isEmpty ? nil : gltfMesh.name,
          numberOfVertices: 0,
          numberOfFaces: 0,
          numberOfBones: 0,
          materialIndex: materialIndex,
          positions: [],
          normals: nil,
          uvs: nil,
          tangents: nil,
          bitangents: nil,
          faces: [],
          bones: []
        )
        return
      }
    } else {
      finalVertexCount = vertexCount
    }

    // Now validate face indices against final vertex count and filter invalid faces
    let validFaces = faces.filter { face in
      guard face.indices.count == 3 else { return false }
      let idx0 = face.indices[0]
      let idx1 = face.indices[1]
      let idx2 = face.indices[2]
      let isValid =
        idx0 >= 0 && idx0 < finalVertexCount && idx1 >= 0 && idx1 < finalVertexCount && idx2 >= 0
        && idx2 < finalVertexCount
      if !isValid {
        // Log detailed information when invalid face is detected
        // This helps diagnose if corruption happened during extraction or later
        logger.warning(
          "⚠️ Invalid vertex index in face: indices=[\(idx0), \(idx1), \(idx2)], finalVertexCount=\(finalVertexCount), mesh='\(gltfMesh.name)'"
        )
        // If we have index accessor info, log it to help diagnose
        if let indices = gltfPrimitive.indices {
          let accessor = indices
          logger.warning(
            "   Accessor info: componentType=\(accessor.componentType), count=\(accessor.count), offset=\(accessor.offset), stride=\(accessor.stride)"
          )
        }
      }
      return isValid
    }

    // Calculate tangent space if needed (like Assimp's calcTangentSpace)
    // If tangents are missing but we have normals and UVs, calculate them from geometry
    if tangents == nil, let normals = normals, let uvs = uvs, !validFaces.isEmpty {
      // Calculate tangents and bitangents from triangle geometry
      var tangentAccum: [vec3] = Array(repeating: vec3(0, 0, 0), count: finalVertexCount)
      var bitangentAccum: [vec3] = Array(repeating: vec3(0, 0, 0), count: finalVertexCount)

      for face in validFaces {
        guard face.indices.count == 3 else { continue }

        let i0 = face.indices[0]
        let i1 = face.indices[1]
        let i2 = face.indices[2]

        // Get positions
        let v0 = vec3(positions[i0 * 3], positions[i0 * 3 + 1], positions[i0 * 3 + 2])
        let v1 = vec3(positions[i1 * 3], positions[i1 * 3 + 1], positions[i1 * 3 + 2])
        let v2 = vec3(positions[i2 * 3], positions[i2 * 3 + 1], positions[i2 * 3 + 2])

        // Get UVs
        let uv0 = vec2(uvs[i0 * 2], uvs[i0 * 2 + 1])
        let uv1 = vec2(uvs[i1 * 2], uvs[i1 * 2 + 1])
        let uv2 = vec2(uvs[i2 * 2], uvs[i2 * 2 + 1])

        // Calculate edge vectors
        let deltaPos1 = v1 - v0
        let deltaPos2 = v2 - v0
        let deltaUV1 = uv1 - uv0
        let deltaUV2 = uv2 - uv0

        // Calculate tangent and bitangent
        let r = 1.0 / (deltaUV1.x * deltaUV2.y - deltaUV1.y * deltaUV2.x)
        let tangent = (deltaPos1 * deltaUV2.y - deltaPos2 * deltaUV1.y) * r
        let bitangent = (deltaPos2 * deltaUV1.x - deltaPos1 * deltaUV2.x) * r

        // Accumulate for each vertex (will be averaged later)
        tangentAccum[i0] = tangentAccum[i0] + tangent
        tangentAccum[i1] = tangentAccum[i1] + tangent
        tangentAccum[i2] = tangentAccum[i2] + tangent

        bitangentAccum[i0] = bitangentAccum[i0] + bitangent
        bitangentAccum[i1] = bitangentAccum[i1] + bitangent
        bitangentAccum[i2] = bitangentAccum[i2] + bitangent
      }

      // Orthonormalize and store tangents and bitangents
      var tangentsArray: [Float] = []
      var bitangentsArray: [Float] = []
      tangentsArray.reserveCapacity(finalVertexCount * 3)
      bitangentsArray.reserveCapacity(finalVertexCount * 3)

      for i in 0..<finalVertexCount {
        let n = vec3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2])
        var t = normalize(tangentAccum[i])
        var b = normalize(bitangentAccum[i])

        // Gram-Schmidt orthogonalization: make tangent orthogonal to normal
        t = normalize(t - dot(t, n) * n)

        // Calculate bitangent from normal and tangent (ensure right-handed)
        b = cross(n, t)

        // Check handedness (bitangent should match accumulated bitangent direction)
        if dot(cross(n, t), b) < 0.0 {
          t = -t
        }

        tangentsArray.append(t.x)
        tangentsArray.append(t.y)
        tangentsArray.append(t.z)

        bitangentsArray.append(b.x)
        bitangentsArray.append(b.y)
        bitangentsArray.append(b.z)
      }

      tangents = tangentsArray
      bitangents = bitangentsArray
    } else if let normals = normals, let tangents = tangents, normals.count == tangents.count {
      // Calculate bitangents from normals and tangents if tangents are provided
      var bitangentsArray: [Float] = []
      bitangentsArray.reserveCapacity(normals.count)
      for i in stride(from: 0, to: normals.count, by: 3) {
        let n = vec3(normals[i], normals[i + 1], normals[i + 2])
        let t = vec3(tangents[i], tangents[i + 1], tangents[i + 2])
        let b = cross(n, t)
        bitangentsArray.append(b.x)
        bitangentsArray.append(b.y)
        bitangentsArray.append(b.z)
      }
      bitangents = bitangentsArray
    }

    // Initialize all properties using designated initializer
    self.init(
      name: gltfMesh.name.isEmpty ? nil : gltfMesh.name,
      numberOfVertices: finalVertexCount,
      numberOfFaces: validFaces.count,
      numberOfBones: 0,
      materialIndex: materialIndex,
      positions: positions,
      normals: normals,
      uvs: uvs,
      tangents: tangents,
      bitangents: bitangents,
      faces: validFaces,
      bones: []
    )
  }
}

extension Material {
  /// Initialize from a GLTF Material
  public init(
    _ gltfMaterial: GLTFMaterial, materialIndex: Int, document: GLTFDocument, imageToEmbeddedIndex: [String: Int] = [:]
  ) {
    // Helper function to get texture path
    func getTexturePath(from textureView: GLTFTextureView, document: GLTFDocument, imageToEmbeddedIndex: [String: Int])
      -> String?
    {
      guard let texture = textureView.texture,
        let image = texture.image
      else {
        return nil
      }

      // Check if it's an embedded texture (buffer view)
      if image.bufferView != nil {
        // This is an embedded texture - find the index in the embeddedTextures array
        // Note: cName returns "<unnamed>" for empty strings, so we need to check for that
        let hasName = !image.name.isEmpty && image.name != "<unnamed>"
        let hasUri = !image.uri.isEmpty && image.uri != "<unnamed>"

        logger.debug(
          "Looking up embedded texture: name='\(image.name)', uri='\(image.uri)', hasName=\(hasName), hasUri=\(hasUri)")

        // Try matching by name first (most reliable)
        if hasName, let embeddedIndex = imageToEmbeddedIndex[image.name] {
          logger.debug("Found embedded texture by name: '\(image.name)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        // Try matching by URI
        if hasUri, let embeddedIndex = imageToEmbeddedIndex[image.uri] {
          logger.debug("Found embedded texture by URI: '\(image.uri)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        // Try the combined identifier (name or URI or index)
        let imageIdentifier = hasName ? image.name : (hasUri ? image.uri : "")
        if !imageIdentifier.isEmpty, let embeddedIndex = imageToEmbeddedIndex[imageIdentifier] {
          logger.debug("Found embedded texture by identifier: '\(imageIdentifier)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        // If no match found, this shouldn't happen but log a warning
        logger.warning(
          "Could not find embedded texture index for image: name='\(image.name)', uri='\(image.uri)'. Available keys: \(Array(imageToEmbeddedIndex.keys).prefix(10))"
        )
      }

      // External texture - return the URI (but not if it's "<unnamed>")
      if !image.uri.isEmpty && image.uri != "<unnamed>" {
        return image.uri
      }

      return nil
    }

    self.name = gltfMaterial.name.isEmpty ? nil : gltfMaterial.name
    self.materialIndex = materialIndex

    // Extract PBR properties
    var baseColor: vec3
    var opacity: Float
    var metallic: Float
    var roughness: Float
    var diffuseTexturePath: String?
    var metallicTexturePath: String?
    var roughnessTexturePath: String?

    if gltfMaterial.hasPBRMetallicRoughness {
      let pbr = gltfMaterial.pbrMetallicRoughness
      let baseColorFactor = pbr.baseColorFactor
      baseColor = vec3(baseColorFactor.0, baseColorFactor.1, baseColorFactor.2)
      opacity = baseColorFactor.3
      metallic = pbr.metallicFactor
      roughness = pbr.roughnessFactor

      // Extract texture paths
      if pbr.baseColorTexture.texture != nil {
        diffuseTexturePath = getTexturePath(
          from: pbr.baseColorTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
      }

      if pbr.metallicRoughnessTexture.texture != nil {
        // Metallic-roughness texture contains both in one texture
        metallicTexturePath = getTexturePath(
          from: pbr.metallicRoughnessTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
        roughnessTexturePath = metallicTexturePath
      }
    } else {
      baseColor = vec3(0.8, 0.8, 0.8)
      opacity = 1.0
      metallic = 0.0
      roughness = 0.5
    }

    // Extract normal texture
    var normalTexturePath: String?
    if gltfMaterial.normalTexture.texture != nil {
      normalTexturePath = getTexturePath(
        from: gltfMaterial.normalTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
    }

    // Extract AO texture (occlusion)
    var aoTexturePath: String?
    if gltfMaterial.occlusionTexture.texture != nil {
      aoTexturePath = getTexturePath(
        from: gltfMaterial.occlusionTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
    }

    // Extract emissive
    let emissiveFactor = gltfMaterial.emissiveFactor
    let emissive = vec3(emissiveFactor[0], emissiveFactor[1], emissiveFactor[2])

    // Now initialize all properties
    self.baseColor = baseColor
    self.opacity = opacity
    self.metallic = metallic
    self.roughness = roughness
    self.emissive = emissive
    self.diffuseTexturePath = diffuseTexturePath
    self.normalTexturePath = normalTexturePath
    self.metallicTexturePath = metallicTexturePath
    self.roughnessTexturePath = roughnessTexturePath
    self.aoTexturePath = aoTexturePath
  }
}

extension Animation {
  /// Initialize from a GLTF Animation
  public init(_ gltfAnimation: GLTFAnimation, document: GLTFDocument) {
    self.name = gltfAnimation.name.isEmpty ? nil : gltfAnimation.name

    // Find max time across all samplers
    var maxTime: Double = 0.0
    var ticksPerSecond: Double = 1.0

    for sampler in gltfAnimation.samplers {
      if let inputData = extractAccessorData(sampler.input) {
        if let lastTime = inputData.last {
          maxTime = max(maxTime, Double(lastTime))
        }
      }
    }

    self.duration = maxTime
    self.ticksPerSecond = ticksPerSecond

    // Convert channels
    var channelsByNode: [String: AnimationChannel] = [:]

    for channel in gltfAnimation.channels {
      guard let node = channel.targetNode else { continue }
      let nodeName = node.name

      let sampler = channel.sampler
      guard let inputData = extractAccessorData(sampler.input),
        let outputData = extractAccessorData(sampler.output)
      else {
        continue
      }

      var positionKeys: [VectorKey] = []
      var rotationKeys: [QuatKey] = []
      var scalingKeys: [VectorKey] = []

      switch channel.targetPath {
      case .translation:
        for i in 0..<min(inputData.count, outputData.count / 3) {
          let time = Double(inputData[i])
          let value = vec3(outputData[i * 3], outputData[i * 3 + 1], outputData[i * 3 + 2])
          positionKeys.append(VectorKey(time: time, value: value))
        }
      case .rotation:
        for i in 0..<min(inputData.count, outputData.count / 4) {
          let time = Double(inputData[i])
          let q = Quaternion<Float>(
            outputData[i * 4 + 3],  // w
            outputData[i * 4 + 0],  // x
            outputData[i * 4 + 1],  // y
            outputData[i * 4 + 2]  // z
          )
          rotationKeys.append(QuatKey(time: time, value: q))
        }
      case .scale:
        for i in 0..<min(inputData.count, outputData.count / 3) {
          let time = Double(inputData[i])
          let value = vec3(outputData[i * 3], outputData[i * 3 + 1], outputData[i * 3 + 2])
          scalingKeys.append(VectorKey(time: time, value: value))
        }
      default:
        break
      }

      // Merge with existing channel or create new
      if let existing = channelsByNode[nodeName] {
        channelsByNode[nodeName] = AnimationChannel(
          nodeName: nodeName,
          positionKeys: existing.positionKeys + positionKeys,
          rotationKeys: existing.rotationKeys + rotationKeys,
          scalingKeys: existing.scalingKeys + scalingKeys
        )
      } else {
        channelsByNode[nodeName] = AnimationChannel(
          nodeName: nodeName,
          positionKeys: positionKeys,
          rotationKeys: rotationKeys,
          scalingKeys: scalingKeys
        )
      }
    }

    self.channels = Array(channelsByNode.values)
  }
}

// MARK: - Scene GLTF Conversion

extension Scene {
  /// Initialize a Scene from a GLTF Document.
  /// Converts GLTF meshes, materials, cameras, animations, and node hierarchy into our Scene representation.
  /// - Parameters:
  ///   - gltfDocument: The GLTF document to convert
  ///   - filePath: Path to the GLTF file
  ///   - skipMaterials: If true, skip material conversion (useful for MapView where materials aren't needed)
  public convenience init(_ gltfDocument: GLTFDocument, filePath: String, skipMaterials: Bool = false) {
    // Log which scene is being loaded for debugging
    let sceneName = URL(fileURLWithPath: filePath).lastPathComponent
    logger.debug("📦 Loading GLTF scene: '\(sceneName)' from path: \(filePath)")

    // Keep the GLTF document alive for the Scene's lifetime
    // The document's deinit calls cgltf_free() which frees all buffer data

    // Extract all data from GLTF buffers first, before processing
    // This ensures all buffer reads happen while the document is guaranteed to be alive
    // We use a two-pass approach: extract all data first, then process it.

    // Build a map from image to embedded texture index for fast lookup
    var imageToEmbeddedIndex: [String: Int] = [:]  // Maps image identifier to embedded texture index

    // FIRST PASS: Extract all mesh data into temporary structures
    // This ensures all cgltf buffer reads complete before we start processing
    struct ExtractedMeshData {
      let name: String
      let positions: [Float]
      let normals: [Float]?
      let uvs: [Float]?
      let tangents: [Float]?
      let indexData: [UInt32]?
      let vertexCount: Int
      let materialIndex: Int
    }

    var extractedMeshData: [ExtractedMeshData] = []
    var meshIndexMap: [Int: [Int]] = [:]  // Maps GLTF mesh index to our mesh indices
    var gltfMeshPtrToIndex: [UnsafeRawPointer: Int] = [:]

    // Extract all mesh data first
    for (gltfMeshIndex, gltfMesh) in gltfDocument.meshes.enumerated() {
      let meshPtr = UnsafeRawPointer(gltfMesh.underlying)
      gltfMeshPtrToIndex[meshPtr] = gltfMeshIndex

      var meshIndices: [Int] = []
      for primitive in gltfMesh.primitives {
        let materialIndex =
          gltfDocument.materials.firstIndex { material in
            primitive.material?.name == material.name
          } ?? 0

        // Extract all data immediately
        var positions: [Float] = []
        var normals: [Float]?
        var uvs: [Float]?
        var tangents: [Float]?
        var vertexCount = 0
        var indexData: [UInt32]? = nil

        // Extract vertex attributes
        for attribute in primitive.attributes {
          switch attribute.type {
          case .position:
            if let data = extractAccessorData(attribute.data) {
              positions = data
              vertexCount = attribute.data.count
            }
          case .normal:
            normals = extractAccessorData(attribute.data)
          case .texcoord:
            if attribute.index == 0 {
              uvs = extractAccessorData(attribute.data)
            }
          case .tangent:
            tangents = extractAccessorData(attribute.data)
          default:
            break
          }
        }

        // Extract indices
        if let indices = primitive.indices {
          // Log accessor details BEFORE extraction to help diagnose
          logger.debug(
            "🔍 Extracting indices for mesh '\(gltfMesh.name)': accessor='\(indices.name)', componentType=\(indices.componentType), count=\(indices.count), offset=\(indices.offset)"
          )
          if let bufferView = indices.bufferView {
            logger.debug(
              "   BufferView: offset=\(bufferView.offset), size=\(bufferView.size), stride=\(bufferView.stride)"
            )
            if let buffer = bufferView.buffer {
              logger.debug("   Buffer: size=\(buffer.size), hasDataPointer=\(buffer.dataPointer != nil)")
              if let dataPtr = buffer.dataPointer {
                logger.debug("   Buffer data pointer: \(String(describing: dataPtr))")
              }
            }
          }

          var extractedIndices = extractIndices(indices)

          // Validate extracted indices
          if var extracted = extractedIndices {
            let maxIndex = extracted.max() ?? 0
            let minIndex = extracted.min() ?? 0

            // Validate indices are reasonable
            if maxIndex > 1000000 {
              logger.error(
                "❌ IMMEDIATE CORRUPTION DETECTED in mesh '\(gltfMesh.name)': Max index \(maxIndex) is absurdly large right after extraction!"
              )
              // Log accessor details
              logger.error(
                "   Accessor: componentType=\(indices.componentType), count=\(indices.count), offset=\(indices.offset), stride=\(indices.stride)"
              )
              if let bufferView = indices.bufferView {
                logger.error(
                  "   BufferView: offset=\(bufferView.offset), size=\(bufferView.size), stride=\(bufferView.stride)"
                )
                if let buffer = bufferView.buffer {
                  logger.error("   Buffer: size=\(buffer.size), hasDataPointer=\(buffer.dataPointer != nil)")
                }
              }
              // Don't use corrupted data
              extractedIndices = nil
            } else if vertexCount > 0 && maxIndex >= UInt32(vertexCount) {
              // Validate against vertex count if we have it
              logger.error(
                "❌ IMMEDIATE CORRUPTION DETECTED in mesh '\(gltfMesh.name)': Max index \(maxIndex) >= vertexCount \(vertexCount) right after extraction!"
              )
              logger.error("   First 10 indices: \(Array(extracted.prefix(10)))")
              logger.error("   Index range: [\(minIndex), \(maxIndex)]")
              // Log the accessor details again for debugging
              logger.error(
                "   Accessor: componentType=\(indices.componentType), count=\(indices.count), offset=\(indices.offset), stride=\(indices.stride)"
              )
              if let bufferView = indices.bufferView {
                logger.error(
                  "   BufferView: offset=\(bufferView.offset), size=\(bufferView.size), stride=\(bufferView.stride)"
                )
                if let buffer = bufferView.buffer {
                  logger.error("   Buffer: size=\(buffer.size), hasDataPointer=\(buffer.dataPointer != nil)")
                  if let dataPtr = buffer.dataPointer {
                    logger.error("   Buffer data pointer: \(String(describing: dataPtr))")
                  }
                }
              }
              // Don't use corrupted data
              extractedIndices = nil
            }
          } else {
            logger.error(
              "❌ extractIndices returned nil for mesh '\(gltfMesh.name)' accessor '\(indices.name)'"
            )
          }

          indexData = extractedIndices
        }

        extractedMeshData.append(
          ExtractedMeshData(
            name: gltfMesh.name,
            positions: positions,
            normals: normals,
            uvs: uvs,
            tangents: tangents,
            indexData: indexData,
            vertexCount: vertexCount,
            materialIndex: materialIndex
          ))

        meshIndices.append(extractedMeshData.count - 1)
      }
      meshIndexMap[gltfMeshIndex] = meshIndices
    }

    // SECOND PASS: Convert extracted data into Mesh objects
    // All buffer reads are now complete, so we can safely process the data
    var allMeshes: [Mesh] = []

    for extracted in extractedMeshData {
      // Validate extracted data before creating mesh
      // Check for obvious corruption
      if let indexData = extracted.indexData {
        let maxIndex = indexData.max() ?? 0
        if maxIndex > 1000000 {
          logger.error(
            "❌ Mesh '\(extracted.name)': Corrupted index data detected after extraction - max index: \(maxIndex), vertexCount: \(extracted.vertexCount)"
          )
          // Skip this mesh or create empty one
          continue
        }

        // Validate indices are within reasonable bounds
        if extracted.vertexCount > 0 && maxIndex >= UInt32(extracted.vertexCount) {
          logger.error(
            "❌ Mesh '\(extracted.name)': Index out of bounds after extraction - max index: \(maxIndex), vertexCount: \(extracted.vertexCount)"
          )
          // Filter out invalid indices or skip mesh
          continue
        }
      }

      // Validate positions
      let expectedPositionCount = extracted.vertexCount * 3
      if extracted.positions.count != expectedPositionCount {
        logger.error(
          "❌ Mesh '\(extracted.name)': Position count mismatch after extraction - expected: \(expectedPositionCount), got: \(extracted.positions.count)"
        )
        // Try to recover or skip
        if extracted.positions.count < 3 {
          continue
        }
      }

      let mesh = Mesh(
        name: extracted.name.isEmpty ? nil : extracted.name,
        positions: extracted.positions,
        normals: extracted.normals,
        uvs: extracted.uvs,
        tangents: extracted.tangents,
        indexData: extracted.indexData,
        vertexCount: extracted.vertexCount,
        materialIndex: extracted.materialIndex
      )
      allMeshes.append(mesh)
    }

    // Convert embedded textures and build mapping FIRST (before materials need them)
    var embeddedTextureIndex = 0
    let embeddedTextures: [EmbeddedTexture] = gltfDocument.images.enumerated().compactMap { documentIndex, image in
      guard let bufferView = image.bufferView,
        let dataPtr = bufferView.dataPointer
      else {
        return nil
      }

      // Map this image to its embedded texture index
      // Use name if available, otherwise URI, otherwise document index as fallback
      // Note: cName returns "<unnamed>" for empty strings, so we need to check for that
      let hasName = !image.name.isEmpty && image.name != "<unnamed>"
      let hasUri = !image.uri.isEmpty && image.uri != "<unnamed>"
      let imageIdentifier = hasName ? image.name : (hasUri ? image.uri : "\(documentIndex)")
      imageToEmbeddedIndex[imageIdentifier] = embeddedTextureIndex

      // Also map by name and URI separately for fallback matching
      if hasName {
        imageToEmbeddedIndex[image.name] = embeddedTextureIndex
        logger.debug("Mapped embedded texture [\(embeddedTextureIndex)]: name='\(image.name)'")
      }
      if hasUri {
        imageToEmbeddedIndex[image.uri] = embeddedTextureIndex
        logger.debug("Mapped embedded texture [\(embeddedTextureIndex)]: uri='\(image.uri)'")
      }
      if !hasName && !hasUri {
        logger.debug("Mapped embedded texture [\(embeddedTextureIndex)]: documentIndex=\(documentIndex)")
      }

      // Use bufferView.dataPointer which already includes the offset
      let data = Data(bytes: dataPtr, count: bufferView.size)
      // We don't know width/height from buffer view alone, would need to decode image
      // For now, use placeholder values
      let embeddedTexture = EmbeddedTexture(
        index: embeddedTextureIndex,
        data: data,
        width: 0,  // Would need to decode to get actual dimensions
        height: 0,
        formatHint: image.mimeType.isEmpty ? nil : image.mimeType
      )
      logger.debug(
        "Created embedded texture [\(embeddedTextureIndex)]: size=\(data.count) bytes, mimeType='\(image.mimeType)', identifier='\(imageIdentifier)'"
      )
      embeddedTextureIndex += 1
      return embeddedTexture
    }

    logger.debug("Total embedded textures: \(embeddedTextures.count), mapping entries: \(imageToEmbeddedIndex.count)")

    // Convert materials (pass the imageToEmbeddedIndex map - now it's populated!)
    // Skip if skipMaterials is true (useful for MapView where materials aren't needed)
    let materials: [Material]
    if skipMaterials {
      materials = []
    } else {
      materials = gltfDocument.materials.enumerated().map { index, gltfMaterial in
        Material(gltfMaterial, materialIndex: index, document: gltfDocument, imageToEmbeddedIndex: imageToEmbeddedIndex)
      }
    }

    // Convert animations
    let animations = gltfDocument.animations.map { Animation($0, document: gltfDocument) }

    // Convert cameras
    let cameras = gltfDocument.cameras.map { gltfCamera in
      Camera(gltfCamera: gltfCamera)
    }

    // Create mapping from GLTF camera name to Camera object for fast lookup
    var gltfCameraNameToCamera: [String: Camera] = [:]
    for (index, gltfCamera) in gltfDocument.cameras.enumerated() {
      let cameraName = gltfCamera.name.isEmpty ? "<unnamed>" : gltfCamera.name
      gltfCameraNameToCamera[cameraName] = cameras[index]
    }

    // Mapping from camera node base name to Camera object
    // This is needed because GLTF allows camera objects to have different names than their nodes
    var cameraNodeToCamera: [String: Camera] = [:]

    // Convert node hierarchy
    func convertNode(
      _ gltfNode: GLTFNode, gltfDocument: GLTFDocument, meshIndexMap: [Int: [Int]],
      gltfMeshPtrToIndex: [UnsafeRawPointer: Int]
    ) -> Node {
      // Get transformation matrix using the wrapper's method
      // This uses cgltf's built-in function to compute the local transform matrix
      let cgltfMatrix = gltfNode.localTransformMatrix

      // cgltf stores matrices in column-major order
      // Construct mat4 from 4 vec4 columns
      let transformation = mat4(
        vec4(cgltfMatrix[0], cgltfMatrix[1], cgltfMatrix[2], cgltfMatrix[3]),  // first column
        vec4(cgltfMatrix[4], cgltfMatrix[5], cgltfMatrix[6], cgltfMatrix[7]),  // second column
        vec4(cgltfMatrix[8], cgltfMatrix[9], cgltfMatrix[10], cgltfMatrix[11]),  // third column
        vec4(cgltfMatrix[12], cgltfMatrix[13], cgltfMatrix[14], cgltfMatrix[15])  // fourth column
      )

      // Get mesh indices - use underlying pointer for accurate matching
      var meshIndices: [Int] = []
      if let gltfMesh = gltfNode.mesh {
        // Now that underlying is accessible, we can directly compare pointers
        let meshPtr = UnsafeRawPointer(gltfMesh.underlying)
        if let gltfMeshIndex = gltfMeshPtrToIndex[meshPtr] {
          meshIndices = meshIndexMap[gltfMeshIndex] ?? []
          if meshIndices.isEmpty {
            logger.warning(
              "Node '\(gltfNode.name)' found GLTF mesh index \(gltfMeshIndex) but meshIndexMap returned empty array")
          }
        } else {
          // Debug: This shouldn't happen if pointer matching is working
          logger.warning(
            "Node '\(gltfNode.name)' references mesh '\(gltfMesh.name)' but couldn't find it in gltfMeshPtrToIndex (map has \(gltfMeshPtrToIndex.count) entries)"
          )
        }
      }

      // If this node has a camera, map it to the Camera object
      // GLTF allows camera objects to have different names than their nodes
      if let gltfCamera = gltfNode.camera {
        let cameraName = gltfCamera.name.isEmpty ? "<unnamed>" : gltfCamera.name
        if let camera = gltfCameraNameToCamera[cameraName] {
          // Extract base name from node name (e.g., "@Camera 1" -> "1")
          let baseName = Scene.extractBaseName(from: gltfNode.name)
          cameraNodeToCamera[baseName] = camera
        }
      }

      // Convert children
      let children = gltfNode.children.map {
        convertNode($0, gltfDocument: gltfDocument, meshIndexMap: meshIndexMap, gltfMeshPtrToIndex: gltfMeshPtrToIndex)
      }

      // Parse GLTF extras into metadata
      let gltfMetadata: NodeMetadata?
      if let extrasJSON = gltfNode.extrasJSON {
        gltfMetadata = NodeMetadata(from: extrasJSON)
      } else {
        gltfMetadata = nil
      }

      let node = Node(
        name: gltfNode.name,
        transformation: transformation,
        meshes: meshIndices,
        children: children
      )

      // Store GLTF metadata
      node._gltfMetadata = gltfMetadata

      return node
    }

    // Find root nodes (nodes without parents)
    let rootNodes = gltfDocument.nodes.filter { $0.parent == nil }

    // Create a root node that contains all root nodes as children
    let rootNode: Node
    if rootNodes.count == 1 {
      rootNode = convertNode(
        rootNodes[0], gltfDocument: gltfDocument, meshIndexMap: meshIndexMap, gltfMeshPtrToIndex: gltfMeshPtrToIndex)
    } else {
      // Multiple root nodes - create a synthetic root
      let children = rootNodes.map {
        convertNode($0, gltfDocument: gltfDocument, meshIndexMap: meshIndexMap, gltfMeshPtrToIndex: gltfMeshPtrToIndex)
      }
      rootNode = Node(name: "Root", transformation: mat4(1), meshes: [], children: children)
    }

    // Call designated initializer
    self.init(
      filePath: filePath,
      rootNode: rootNode,
      meshes: allMeshes,
      materials: materials,
      cameras: cameras,
      animations: animations,
      embeddedTextures: embeddedTextures
    )

    // Store the camera node to camera mapping
    self._cameraNodeToCamera = cameraNodeToCamera

    // _gltfDocument was already set at the start of the initializer to keep the document alive
  }
}

// Helper to convert quaternion to matrix
private func quaternionToMatrix(_ q: Quaternion<Float>) -> mat4 {
  let x = q.x
  let y = q.y
  let z = q.z
  let w = q.w

  let x2 = x + x
  let y2 = y + y
  let z2 = z + z

  let xx = x * x2
  let xy = x * y2
  let xz = x * z2
  let yy = y * y2
  let yz = y * z2
  let zz = z * z2
  let wx = w * x2
  let wy = w * y2
  let wz = w * z2

  return mat4(
    1 - (yy + zz), xy + wz, xz - wy, 0,
    xy - wz, 1 - (xx + zz), yz + wx, 0,
    xz + wy, yz - wx, 1 - (xx + yy), 0,
    0, 0, 0, 1
  )
}
