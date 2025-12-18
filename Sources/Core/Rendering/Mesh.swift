/// TODO: docs
public struct Mesh {
  public let name: String?
  public let numberOfVertices: Int
  public let numberOfFaces: Int
  public let numberOfBones: Int
  public let materialIndex: Int

  // Vertex data
  public let positions: [Float]  // numberOfVertices * 3
  public let normals: [Float]?  // numberOfVertices * 3
  public let uvs: [Float]?  // numberOfVertices * 2 (first UV channel)
  public let tangents: [Float]?  // numberOfVertices * 3
  public let bitangents: [Float]?  // numberOfVertices * 3

  // Face data
  public let faces: [Face]

  // Bone data
  public let bones: [Bone]

  public init(
    name: String? = nil,
    numberOfVertices: Int,
    numberOfFaces: Int,
    numberOfBones: Int = 0,
    materialIndex: Int = 0,
    positions: [Float],
    normals: [Float]? = nil,
    uvs: [Float]? = nil,
    tangents: [Float]? = nil,
    bitangents: [Float]? = nil,
    faces: [Face],
    bones: [Bone] = []
  ) {
    self.name = name
    self.numberOfVertices = numberOfVertices
    self.numberOfFaces = numberOfFaces
    self.numberOfBones = numberOfBones
    self.materialIndex = materialIndex
    self.positions = positions
    self.normals = normals
    self.uvs = uvs
    self.tangents = tangents
    self.bitangents = bitangents
    self.faces = faces
    self.bones = bones
  }
}

/// Face representing a triangle (3 vertex indices)
public struct Face {
  public let indices: [Int]

  public init(indices: [Int]) {
    self.indices = indices
  }
}

/// Bone data for skeletal animation
public struct Bone {
  public let name: String?
  public let offsetMatrix: mat4  // Transform from mesh space to bone space in bind pose
  public let weights: [VertexWeight]

  public init(name: String?, offsetMatrix: mat4, weights: [VertexWeight]) {
    self.name = name
    self.offsetMatrix = offsetMatrix
    self.weights = weights
  }
}

/// Vertex weight for bone influence
public struct VertexWeight {
  public let vertexIndex: Int
  public let weight: Float

  public init(vertexIndex: Int, weight: Float) {
    self.vertexIndex = vertexIndex
    self.weight = weight
  }
}

extension Mesh {
  /// Calculate bounding box for a mesh with a transform
  public func calculateBoundingBox(transform: mat4) -> (min: vec3, max: vec3) {
    var minX: Float = Float.infinity
    var maxX: Float = -Float.infinity
    var minY: Float = Float.infinity
    var maxY: Float = -Float.infinity
    var minZ: Float = Float.infinity
    var maxZ: Float = -Float.infinity

    for i in 0..<numberOfVertices {
      let localPos = vec3(
        positions[i * 3 + 0],
        positions[i * 3 + 1],
        positions[i * 3 + 2]
      )
      let worldPos = transform * vec4(localPos.x, localPos.y, localPos.z, 1.0)
      minX = min(minX, worldPos.x)
      maxX = max(maxX, worldPos.x)
      minY = min(minY, worldPos.y)
      maxY = max(maxY, worldPos.y)
      minZ = min(minZ, worldPos.z)
      maxZ = max(maxZ, worldPos.z)
    }

    return (min: vec3(minX, minY, minZ), max: vec3(maxX, maxY, maxZ))
  }
}
