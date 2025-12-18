import CGLTF
import GLTF
import GLMath

private let minWeightThreshold: Float = 0.0001
private let normalizedByteScale: Float = 255.0
private let normalizedShortScale: Float = 65535.0

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
    materialIndex: Int,
    numberOfBones: Int = 0,
    bones: [Bone] = []
  ) {
    var bitangents: [Float]?
    let finalVertexCount: Int

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

    var faces: [Face] = []
    if let indexData = indexData {
      let maxIndexInData = indexData.max() ?? 0
      if maxIndexInData >= UInt32(finalVertexCount) {
        logger.error(
          "❌ Mesh '\(name ?? "<unnamed>")': Index data appears corrupted - max index is \(maxIndexInData) but vertexCount is only \(finalVertexCount)"
        )
      }

      for i in stride(from: 0, to: indexData.count, by: 3) {
        if i + 2 < indexData.count {
          let idx0 = Int(indexData[i])
          let idx1 = Int(indexData[i + 1])
          let idx2 = Int(indexData[i + 2])

          guard idx0 >= 0 && idx1 >= 0 && idx2 >= 0 else {
            logger.warning("⚠️ Negative vertex index in face: [\(idx0), \(idx1), \(idx2)]")
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

      self.init(
        name: name,
        numberOfVertices: finalVertexCount,
        numberOfFaces: validFaces.count,
        numberOfBones: numberOfBones,
        materialIndex: materialIndex,
        positions: positions,
        normals: normals,
        uvs: uvs,
        tangents: tangentsArray,
        bitangents: bitangentsArray,
        faces: validFaces,
        bones: bones
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
      numberOfBones: numberOfBones,
      materialIndex: materialIndex,
      positions: positions,
      normals: normals,
      uvs: uvs,
      tangents: tangents,
      bitangents: bitangents,
      faces: validFaces,
      bones: bones
    )
  }

  /// Initialize from a GLTF Mesh primitive
  /// Note: GLTF meshes can have multiple primitives, so we create one Mesh per primitive
  public init(_ gltfPrimitive: GLTFPrimitive, gltfMesh: GLTFMesh, materialIndex: Int) {
    var positions: [Float] = []
    var normals: [Float]?
    var uvs: [Float]?
    var tangents: [Float]?
    var bitangents: [Float]?
    var vertexCount = 0

    for attribute in gltfPrimitive.attributes {
      switch attribute.type {
      case .position:
        if let data = attribute.data.unpackFloats() {
          positions = data
          let expectedVertexCount = data.count / 3
          let accessorCount = attribute.data.count
          if expectedVertexCount != accessorCount {
            logger.warning(
              "⚠️ Position count mismatch in mesh '\(gltfMesh.name)': positions.count/3=\(expectedVertexCount), accessor.count=\(accessorCount)"
            )
          }
          vertexCount = accessorCount
        }
      case .normal:
        if let data = attribute.data.unpackFloats() {
          normals = data
        }
      case .texcoord:
        if attribute.index == 0, let data = attribute.data.unpackFloats() {
          uvs = data
        }
      case .tangent:
        if let data = attribute.data.unpackFloats() {
          tangents = data
        }
      default:
        break
      }
    }

    var faces: [Face] = []
    if let indices = gltfPrimitive.indices, let indexData = indices.unpackIndices() {
      let maxIndexInData = indexData.max() ?? 0
      let minIndexInData = indexData.min() ?? 0

      if vertexCount > 0 {
        if maxIndexInData >= UInt32(vertexCount) {
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
        }
      }

      for i in stride(from: 0, to: indexData.count, by: 3) {
        if i + 2 < indexData.count {
          let idx0 = Int(indexData[i])
          let idx1 = Int(indexData[i + 1])
          let idx2 = Int(indexData[i + 2])

          guard idx0 >= 0 && idx1 >= 0 && idx2 >= 0 else {
            logger.warning(
              "⚠️ Negative vertex index in face: indices=[\(idx0), \(idx1), \(idx2)], mesh='\(gltfMesh.name)'")
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
          "⚠️ Invalid vertex index in face: indices=[\(idx0), \(idx1), \(idx2)], finalVertexCount=\(finalVertexCount), mesh='\(gltfMesh.name)'"
        )
        if let indices = gltfPrimitive.indices {
          let accessor = indices
          logger.warning(
            "   Accessor info: componentType=\(accessor.componentType), count=\(accessor.count), offset=\(accessor.offset), stride=\(accessor.stride)"
          )
        }
      }
      return isValid
    }

    // Calculate tangent space if tangents are missing but we have normals and UVs
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

        // Gram-Schmidt orthogonalization: make tangent orthogonal to normal
        t = normalize(t - dot(t, n) * n)

        // Calculate bitangent from normal and tangent (ensure right-handed coordinate system)
        b = cross(n, t)

        // Check handedness: if bitangent direction doesn't match accumulated, flip tangent
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

      if image.bufferView != nil {
        let hasName = !image.name.isEmpty && image.name != "<unnamed>"
        let hasUri = !image.uri.isEmpty && image.uri != "<unnamed>"

        logger.debug(
          "Looking up embedded texture: name='\(image.name)', uri='\(image.uri)', hasName=\(hasName), hasUri=\(hasUri)")

        if hasName, let embeddedIndex = imageToEmbeddedIndex[image.name] {
          logger.debug("Found embedded texture by name: '\(image.name)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        if hasUri, let embeddedIndex = imageToEmbeddedIndex[image.uri] {
          logger.debug("Found embedded texture by URI: '\(image.uri)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        let imageIdentifier = hasName ? image.name : (hasUri ? image.uri : "")
        if !imageIdentifier.isEmpty, let embeddedIndex = imageToEmbeddedIndex[imageIdentifier] {
          logger.debug("Found embedded texture by identifier: '\(imageIdentifier)' -> *\(embeddedIndex)")
          return "*\(embeddedIndex)"
        }
        logger.warning(
          "Could not find embedded texture index for image: name='\(image.name)', uri='\(image.uri)'. Available keys: \(Array(imageToEmbeddedIndex.keys).prefix(10))"
        )
      }

      if !image.uri.isEmpty && image.uri != "<unnamed>" {
        return image.uri
      }

      return nil
    }

    self.name = gltfMaterial.name.isEmpty ? nil : gltfMaterial.name
    self.materialIndex = materialIndex

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

    var normalTexturePath: String?
    if gltfMaterial.normalTexture.texture != nil {
      normalTexturePath = getTexturePath(
        from: gltfMaterial.normalTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
    }

    var aoTexturePath: String?
    if gltfMaterial.occlusionTexture.texture != nil {
      aoTexturePath = getTexturePath(
        from: gltfMaterial.occlusionTexture, document: document, imageToEmbeddedIndex: imageToEmbeddedIndex)
    }

    let emissiveFactor = gltfMaterial.emissiveFactor
    let emissive = vec3(emissiveFactor[0], emissiveFactor[1], emissiveFactor[2])

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
    let ticksPerSecond: Double = 1.0

    for sampler in gltfAnimation.samplers {
      if let inputData = sampler.input.unpackFloats() {
        if let lastTime = inputData.last {
          maxTime = max(maxTime, Double(lastTime))
        }
      }
    }

    self.duration = maxTime
    self.ticksPerSecond = ticksPerSecond

    var channelsByNode: [String: AnimationChannel] = [:]

    for channel in gltfAnimation.channels {
      guard let node = channel.targetNode else { continue }
      let nodeName = node.name

      let sampler = channel.sampler
      guard let inputData = sampler.input.unpackFloats(),
        let outputData = sampler.output.unpackFloats()
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
        // GLTF quaternion order is (x, y, z, w), which matches our Quaternion type
        // Normalize quaternions to ensure they represent pure rotations (no scaling/shear)
        // Non-normalized quaternions can cause unexpected transformations when converted to matrices
        for i in 0..<min(inputData.count, outputData.count / 4) {
          let time = Double(inputData[i])
          let q = Quaternion<Float>(
            outputData[i * 4 + 0],  // x
            outputData[i * 4 + 1],  // y
            outputData[i * 4 + 2],  // z
            outputData[i * 4 + 3]  // w
          )
          let len = sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
          let normalizedQ: Quaternion<Float>
          if len > minWeightThreshold {
            normalizedQ = Quaternion<Float>(q.x / len, q.y / len, q.z / len, q.w / len)
          } else {
            // Fallback to identity quaternion if length is too small (invalid quaternion)
            normalizedQ = Quaternion<Float>(0, 0, 0, 1)
          }
          rotationKeys.append(QuatKey(time: time, value: normalizedQ))
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

extension Light {
  /// Initialize from a GLTF Light
  public init(_ gltfLight: GLTFLight) {
    let lightName = gltfLight.name.isEmpty ? nil : gltfLight.name
    let colorTuple = gltfLight.color
    let color = vec3(colorTuple.0, colorTuple.1, colorTuple.2)

    let lightType: LightType
    switch gltfLight.type {
    case .directional:
      lightType = .directional
    case .point:
      lightType = .point
    case .spot:
      lightType = .spot
    default:
      lightType = .directional
    }

    // GLTF lights: direction defaults to -Z for directional/spot lights, position set from node transform
    let direction = lightType == .point ? vec3(0, -1, 0) : vec3(0, 0, -1)

    let innerConeAngle = lightType == .spot ? gltfLight.spotInnerConeAngle : nil
    let outerConeAngle = lightType == .spot ? gltfLight.spotOuterConeAngle : nil

    self.init(
      name: lightName,
      direction: direction,
      position: vec3(0, 0, 0),  // Will be set from node transform
      color: color,
      intensity: gltfLight.intensity,
      range: gltfLight.range > 0 ? gltfLight.range : 100.0,
      type: lightType,
      innerConeAngle: innerConeAngle,
      outerConeAngle: outerConeAngle
    )
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
    let sceneName = URL(fileURLWithPath: filePath).lastPathComponent
    logger.debug("📦 Loading GLTF scene: '\(sceneName)' from path: \(filePath)")

    // Keep the GLTF document alive for the Scene's lifetime
    // The document's deinit calls cgltf_free() which frees all buffer data
    // We must extract all buffer data before the document could be deallocated

    // Two-pass approach: extract all data first, then process it
    // This ensures all cgltf buffer reads complete while the document is guaranteed to be alive
    var imageToEmbeddedIndex: [String: Int] = [:]

    // FIRST PASS: Extract all mesh data into temporary structures
    // All buffer reads happen here, before any processing that could invalidate pointers
    struct ExtractedMeshData {
      let name: String
      let positions: [Float]
      let normals: [Float]?
      let uvs: [Float]?
      let tangents: [Float]?
      let indexData: [UInt32]?
      let vertexCount: Int
      let materialIndex: Int
      let jointsData: [UInt16]?
      let weightsData: [Float]?
      let gltfMeshIndex: Int
      let primitiveIndex: Int
    }

    var extractedMeshData: [ExtractedMeshData] = []
    var meshIndexMap: [Int: [Int]] = [:]
    var gltfMeshPtrToIndex: [UnsafeRawPointer: Int] = [:]

    for (gltfMeshIndex, gltfMesh) in gltfDocument.meshes.enumerated() {
      let meshPtr = UnsafeRawPointer(gltfMesh.underlying)
      gltfMeshPtrToIndex[meshPtr] = gltfMeshIndex

      var meshIndices: [Int] = []
      for (primitiveIndex, primitive) in gltfMesh.primitives.enumerated() {
        // Find material index by matching primitive's material name with document materials
        // Default to 0 if material not found (some GLTF files may have missing material references)
        let materialIndex =
          gltfDocument.materials.firstIndex { material in
            primitive.material?.name == material.name
          } ?? 0

        var positions: [Float] = []
        var normals: [Float]?
        var uvs: [Float]?
        var tangents: [Float]?
        var jointsData: [UInt16]? = nil
        var weightsData: [Float]? = nil
        var vertexCount = 0
        var indexData: [UInt32]? = nil

        for attribute in primitive.attributes {
          switch attribute.type {
          case .position:
            if let data = attribute.data.unpackFloats() {
              positions = data
              vertexCount = attribute.data.count
            }
          case .normal:
            normals = attribute.data.unpackFloats()
          case .texcoord:
            if attribute.index == 0 {
              uvs = attribute.data.unpackFloats()
            }
          case .tangent:
            tangents = attribute.data.unpackFloats()
          case .joints:
            // JOINTS_0 attribute: bone indices per vertex (usually UNSIGNED_BYTE or UNSIGNED_SHORT, vec4)
            if attribute.index == 0 {
              let componentCount = attribute.data.type == .vec4 ? 4 : (attribute.data.type == .vec3 ? 3 : 1)
              let expectedCount = attribute.data.count * componentCount

              switch attribute.data.componentType {
              case .r_8u:
                // UNSIGNED_BYTE: extract as floats, then convert (handle normalized vs non-normalized)
                if let data = attribute.data.unpackFloats(), data.count >= expectedCount {
                  if attribute.data.normalized {
                    // Normalized [0,1] -> [0,255]
                    jointsData = (0..<expectedCount).map { UInt16(data[$0] * normalizedByteScale) }
                  } else {
                    // Direct conversion
                    jointsData = (0..<expectedCount).map { UInt16(data[$0]) }
                  }
                }
              case .r_16u:
                // UNSIGNED_SHORT: extract as floats, then convert (handle normalized vs non-normalized)
                if let data = attribute.data.unpackFloats(), data.count >= expectedCount {
                  if attribute.data.normalized {
                    // Normalized [0,1] -> [0,65535]
                    jointsData = (0..<expectedCount).map { UInt16(data[$0] * normalizedShortScale) }
                  } else {
                    // Direct conversion
                    jointsData = (0..<expectedCount).map { UInt16(data[$0]) }
                  }
                }
              default:
                // Fallback: try unpackIndices for other component types
                if let indices = attribute.data.unpackIndices() {
                  jointsData = indices.map { UInt16($0) }
                }
              }
            }
          case .weights:
            if attribute.index == 0 {
              weightsData = attribute.data.unpackFloats()
            }
          default:
            break
          }
        }

        // Extract indices
        if let indices = primitive.indices {
          indexData = indices.unpackIndices()
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
            materialIndex: materialIndex,
            jointsData: jointsData,
            weightsData: weightsData,
            gltfMeshIndex: gltfMeshIndex,
            primitiveIndex: primitiveIndex
          ))

        meshIndices.append(extractedMeshData.count - 1)
      }
      meshIndexMap[gltfMeshIndex] = meshIndices
    }

    // SECOND PASS: Convert extracted data into Mesh objects
    var allMeshes: [Mesh] = []

    for extracted in extractedMeshData {

      let expectedPositionCount = extracted.vertexCount * 3
      if extracted.positions.count != expectedPositionCount {
        logger.error(
          "❌ Mesh '\(extracted.name)': Position count mismatch after extraction - expected: \(expectedPositionCount), got: \(extracted.positions.count)"
        )
        if extracted.positions.count < 3 {
          continue
        }
      }

      var bones: [Bone] = []
      if let jointsData = extracted.jointsData, let weightsData = extracted.weightsData {
        logger.debug(
          "🔍 Mesh '\(extracted.name)' has JOINTS_0 (\(jointsData.count) values) and WEIGHTS_0 (\(weightsData.count) values)"
        )

        let gltfMesh = gltfDocument.meshes[extracted.gltfMeshIndex]
        let meshPtr = UnsafeRawPointer(gltfMesh.underlying)

        var owningNode: GLTFNode? = nil
        func findOwningNode(_ gltfNode: GLTFNode) {
          if let nodeMesh = gltfNode.mesh,
            UnsafeRawPointer(nodeMesh.underlying) == meshPtr
          {
            owningNode = gltfNode
            return
          }
          for child in gltfNode.children {
            findOwningNode(child)
          }
        }
        for rootNode in gltfDocument.nodes.filter({ $0.parent == nil }) {
          findOwningNode(rootNode)
          if owningNode != nil { break }
        }

        if owningNode == nil {
          logger.warning("⚠️ Could not find owning node for mesh '\(extracted.name)'")
        } else {
          logger.debug("✅ Found owning node '\(owningNode!.name)' for mesh '\(extracted.name)'")
        }

        if let node = owningNode, let skin = node.skin {
          logger.debug("✅ Node '\(node.name)' has skin with \(skin.joints.count) joints")
          var inverseBindMatrices: [mat4] = []
          if let ibmAccessor = skin.inverseBindMatrices {
            if let matrixData = ibmAccessor.unpackFloats() {
              // Matrices are stored as 16 floats each (column-major)
              let matrixCount = matrixData.count / 16
              for i in 0..<matrixCount {
                let base = i * 16
                let m = mat4(
                  vec4(matrixData[base + 0], matrixData[base + 1], matrixData[base + 2], matrixData[base + 3]),
                  vec4(matrixData[base + 4], matrixData[base + 5], matrixData[base + 6], matrixData[base + 7]),
                  vec4(matrixData[base + 8], matrixData[base + 9], matrixData[base + 10], matrixData[base + 11]),
                  vec4(matrixData[base + 12], matrixData[base + 13], matrixData[base + 14], matrixData[base + 15])
                )
                inverseBindMatrices.append(m)
              }
            }
          }

          let joints = skin.joints
          let jointCount = min(joints.count, inverseBindMatrices.count)

          // JOINTS_0 and WEIGHTS_0 are vec4 (4 components per vertex)
          let vertexCount = extracted.vertexCount
          var boneWeights: [Int: [VertexWeight]] = [:]

          // Collect all weights per vertex and normalize them (similar to Assimp's aiProcess_LimitBoneWeights)
          var vertexWeights: [[(boneIndex: Int, weight: Float)]] = Array(repeating: [], count: vertexCount)

          for vertexIndex in 0..<vertexCount {
            let base = vertexIndex * 4
            if base + 3 < jointsData.count && base + 3 < weightsData.count {
              var weights: [(boneIndex: Int, weight: Float)] = []
              for i in 0..<4 {
                let boneIndex = Int(jointsData[base + i])
                let weight = weightsData[base + i]

                if boneIndex < jointCount && weight > minWeightThreshold {
                  weights.append((boneIndex: boneIndex, weight: weight))
                }
              }

              // Normalize weights so they sum to 1.0 (similar to Assimp's aiProcess_LimitBoneWeights)
              // This ensures proper skinning even if source data has non-normalized weights
              let totalWeight = weights.reduce(0.0) { $0 + $1.weight }
              if totalWeight > minWeightThreshold {
                let normalizationFactor = 1.0 / totalWeight
                for weight in weights {
                  let normalizedWeight = weight.weight * normalizationFactor
                  vertexWeights[vertexIndex].append((boneIndex: weight.boneIndex, weight: normalizedWeight))
                }
              }
            }
          }

          // Build bone-to-vertex-weight mapping from normalized weights
          for vertexIndex in 0..<vertexCount {
            for (boneIndex, weight) in vertexWeights[vertexIndex] {
              if boneWeights[boneIndex] == nil {
                boneWeights[boneIndex] = []
              }
              boneWeights[boneIndex]?.append(VertexWeight(vertexIndex: vertexIndex, weight: weight))
            }
          }

          // CRITICAL: Bones MUST be in the same order as skin.joints
          // JOINTS_0 vertex attribute indices refer directly to skin.joints array indices
          // Changing this order would break all bone index references in vertex data
          for i in 0..<jointCount {
            let jointNode = joints[i]
            let offsetMatrix = i < inverseBindMatrices.count ? inverseBindMatrices[i] : mat4(1)
            let weights = boneWeights[i] ?? []

            bones.append(
              Bone(
                name: jointNode.name.isEmpty ? nil : jointNode.name,
                offsetMatrix: offsetMatrix,
                weights: weights
              ))

            if i < 3 {
              logger.debug("  Bone[\(i)] = '\(jointNode.name)' (from skin.joints[\(i)])")
            }
          }

          logger.debug("📦 Loaded \(bones.count) bones for mesh '\(extracted.name)'")
          if !bones.isEmpty {
            logger.debug("  Bone names: \(bones.compactMap { $0.name })")
            logger.debug("  Bone indices: 0..<\(bones.count)")
            if let firstBone = bones.first {
              logger.debug(
                "  First bone '\(firstBone.name ?? "Unknown")' offset matrix translation: (\(firstBone.offsetMatrix[3].x), \(firstBone.offsetMatrix[3].y), \(firstBone.offsetMatrix[3].z))"
              )
            }
          }
        } else {
          if owningNode != nil {
            logger.warning("⚠️ Node '\(owningNode!.name)' does not have a skin for mesh '\(extracted.name)'")
          }
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
        materialIndex: extracted.materialIndex,
        numberOfBones: bones.count,
        bones: bones
      )
      allMeshes.append(mesh)
    }

    // Convert embedded textures and build mapping (before materials need them)
    var embeddedTextureIndex = 0
    let embeddedTextures: [EmbeddedTexture] = gltfDocument.images.enumerated().compactMap { documentIndex, image in
      guard let bufferView = image.bufferView,
        let dataPtr = bufferView.dataPointer
      else {
        return nil
      }

      // Map image to embedded texture index (use name, URI, or document index as fallback)
      // Note: cgltf returns "<unnamed>" for empty strings, so we check for that explicitly
      let hasName = !image.name.isEmpty && image.name != "<unnamed>"
      let hasUri = !image.uri.isEmpty && image.uri != "<unnamed>"
      let imageIdentifier = hasName ? image.name : (hasUri ? image.uri : "\(documentIndex)")
      imageToEmbeddedIndex[imageIdentifier] = embeddedTextureIndex

      // Also map by name and URI separately for fallback matching during material lookup
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

      let data = Data(bytes: dataPtr, count: bufferView.size)
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

    // Skip materials if requested (useful for MapView where materials aren't needed)
    let materials: [Material]
    if skipMaterials {
      materials = []
    } else {
      materials = gltfDocument.materials.enumerated().map { index, gltfMaterial in
        Material(gltfMaterial, materialIndex: index, document: gltfDocument, imageToEmbeddedIndex: imageToEmbeddedIndex)
      }
    }

    let animations = gltfDocument.animations.map { Animation($0, document: gltfDocument) }

    let cameras = gltfDocument.cameras.map { gltfCamera in
      Camera(gltfCamera: gltfCamera)
    }

    // Create mapping from GLTF camera name to Camera object
    var gltfCameraNameToCamera: [String: Camera] = [:]
    for (index, gltfCamera) in gltfDocument.cameras.enumerated() {
      let cameraName = gltfCamera.name.isEmpty ? "<unnamed>" : gltfCamera.name
      gltfCameraNameToCamera[cameraName] = cameras[index]
    }

    // Mapping from camera node base name to Camera object
    // GLTF allows camera objects to have different names than their nodes
    var cameraNodeToCamera: [String: Camera] = [:]

    // Create mapping from GLTF light to our Light type
    var gltfLightToLight: [UnsafeRawPointer: Light] = [:]
    for gltfLight in gltfDocument.lights {
      let lightPtr = UnsafeRawPointer(gltfLight.underlying)
      gltfLightToLight[lightPtr] = Light(gltfLight)
    }

    var collectedLights: [(light: Light, nodeName: String)] = []

    func convertNode(
      _ gltfNode: GLTFNode, gltfDocument: GLTFDocument, meshIndexMap: [Int: [Int]],
      gltfMeshPtrToIndex: [UnsafeRawPointer: Int]
    ) -> Node {
      // Get transformation matrix using cgltf's built-in function
      // This handles TRS (translation, rotation, scale) decomposition automatically
      let cgltfMatrix = gltfNode.localTransformMatrix

      // cgltf stores matrices in column-major order (OpenGL convention)
      // Construct mat4 from 4 vec4 columns: [col0, col1, col2, col3]
      let transformation = mat4(
        vec4(cgltfMatrix[0], cgltfMatrix[1], cgltfMatrix[2], cgltfMatrix[3]),
        vec4(cgltfMatrix[4], cgltfMatrix[5], cgltfMatrix[6], cgltfMatrix[7]),
        vec4(cgltfMatrix[8], cgltfMatrix[9], cgltfMatrix[10], cgltfMatrix[11]),
        vec4(cgltfMatrix[12], cgltfMatrix[13], cgltfMatrix[14], cgltfMatrix[15])
      )

      var meshIndices: [Int] = []
      if let gltfMesh = gltfNode.mesh {
        let meshPtr = UnsafeRawPointer(gltfMesh.underlying)
        if let gltfMeshIndex = gltfMeshPtrToIndex[meshPtr] {
          meshIndices = meshIndexMap[gltfMeshIndex] ?? []
          if meshIndices.isEmpty {
            logger.warning(
              "Node '\(gltfNode.name)' found GLTF mesh index \(gltfMeshIndex) but meshIndexMap returned empty array")
          }
        } else {
          logger.warning(
            "Node '\(gltfNode.name)' references mesh '\(gltfMesh.name)' but couldn't find it in gltfMeshPtrToIndex (map has \(gltfMeshPtrToIndex.count) entries)"
          )
        }
      }

      // Map camera node to Camera object (GLTF allows camera objects to have different names than their nodes)
      if let gltfCamera = gltfNode.camera {
        let cameraName = gltfCamera.name.isEmpty ? "<unnamed>" : gltfCamera.name
        if let camera = gltfCameraNameToCamera[cameraName] {
          let baseName = Scene.extractBaseName(from: gltfNode.name)
          cameraNodeToCamera[baseName] = camera
        }
      }

      if let gltfLight = gltfNode.light {
        let lightPtr = UnsafeRawPointer(gltfLight.underlying)
        if var light = gltfLightToLight[lightPtr] {
          if light.name == nil || light.name!.isEmpty {
            light.name = gltfNode.name.isEmpty ? nil : gltfNode.name
          }
          let nodeTransform = transformation
          let position = vec3(nodeTransform[3].x, nodeTransform[3].y, nodeTransform[3].z)
          // Default direction is -Z in GLTF, transform it by the node's rotation
          if light.type != .point {
            let defaultDir = vec3(0, 0, -1)
            let rotMatrix = mat3(
              vec3(nodeTransform[0].x, nodeTransform[0].y, nodeTransform[0].z),
              vec3(nodeTransform[1].x, nodeTransform[1].y, nodeTransform[1].z),
              vec3(nodeTransform[2].x, nodeTransform[2].y, nodeTransform[2].z)
            )
            let transformedDir = normalize(rotMatrix * defaultDir)
            light.direction = transformedDir
          }
          light.position = position
          collectedLights.append((light: light, nodeName: gltfNode.name))
        }
      }

      let children = gltfNode.children.map {
        convertNode($0, gltfDocument: gltfDocument, meshIndexMap: meshIndexMap, gltfMeshPtrToIndex: gltfMeshPtrToIndex)
      }

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

      node._gltfMetadata = gltfMetadata

      return node
    }

    let rootNodes = gltfDocument.nodes.filter { $0.parent == nil }

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

    let lights = collectedLights.map { $0.light }

    self.init(
      filePath: filePath,
      rootNode: rootNode,
      meshes: allMeshes,
      materials: materials,
      cameras: cameras,
      lights: lights,
      animations: animations,
      embeddedTextures: embeddedTextures
    )

    self._cameraNodeToCamera = cameraNodeToCamera
  }
}
