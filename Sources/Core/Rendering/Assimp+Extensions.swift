import Assimp
import GLMath

// MARK: - Assimp.Matrix4x4 Extension

extension Assimp.Matrix4x4 {
  /// Convert Assimp matrix to GLMath mat4
  /// Assimp stores matrices in row-major order (a1-a4 is first row)
  var mat4Representation: mat4 {
    let row1 = vec4(Float(a1), Float(b1), Float(c1), Float(d1))
    let row2 = vec4(Float(a2), Float(b2), Float(c2), Float(d2))
    let row3 = vec4(Float(a3), Float(b3), Float(c3), Float(d3))
    let row4 = vec4(Float(a4), Float(b4), Float(c4), Float(d4))
    return mat4(row1, row2, row3, row4)
  }
}

// MARK: - Assimp.Node Extension

extension Assimp.Node {
  /// Calculate world transform for a node by traversing up the hierarchy
  func calculateWorldTransform(scene: Assimp.Scene) -> mat4 {
    var transform = transformation.mat4Representation
    var currentNode: Assimp.Node? = self

    while let parent = currentNode?.parent {
      let parentTransform = parent.transformation.mat4Representation
      transform = parentTransform * transform
      currentNode = parent
    }

    return transform
  }

  /// Calculate bounding box for a node's meshes in world space
  func calculateBoundingBox(transform: mat4, in scene: Assimp.Scene) -> (min: vec3, max: vec3) {
    var minBounds = vec3(Float.infinity, Float.infinity, Float.infinity)
    var maxBounds = vec3(-Float.infinity, -Float.infinity, -Float.infinity)

    // Process all meshes attached to this node
    for meshIndex in meshes {
      guard meshIndex < scene.meshes.count else { continue }
      let mesh = scene.meshes[meshIndex]

      // Get vertices from mesh
      let vertices = mesh.vertices
      guard mesh.numberOfVertices > 0 else { continue }

      // Transform each vertex to world space and expand bounding box
      for i in 0..<mesh.numberOfVertices {
        let localPos = vec3(
          Float(vertices[i * 3 + 0]),
          Float(vertices[i * 3 + 1]),
          Float(vertices[i * 3 + 2])
        )

        // Transform to world space
        let worldPos = transform * vec4(localPos.x, localPos.y, localPos.z, 1.0)
        let worldVec = vec3(worldPos.x, worldPos.y, worldPos.z)

        minBounds.x = min(minBounds.x, worldVec.x)
        minBounds.y = min(minBounds.y, worldVec.y)
        minBounds.z = min(minBounds.z, worldVec.z)

        maxBounds.x = max(maxBounds.x, worldVec.x)
        maxBounds.y = max(maxBounds.y, worldVec.y)
        maxBounds.z = max(maxBounds.z, worldVec.z)
      }
    }

    // If no meshes found, return a small default box around the position
    if minBounds.x == Float.infinity {
      let position = vec3(transform[3].x, transform[3].y, transform[3].z)
      let defaultSize: Float = 1.0
      return (
        min: position - vec3(defaultSize, defaultSize, defaultSize),
        max: position + vec3(defaultSize, defaultSize, defaultSize)
      )
    }

    return (min: minBounds, max: maxBounds)
  }
}

// MARK: - Assimp.Mesh Extension

extension Assimp.Mesh {
  /// Calculate bounding box for a mesh with a transform
  func calculateBoundingBox(transform: mat4) -> (min: vec3, max: vec3) {
    var minX: Float = Float.infinity
    var maxX: Float = -Float.infinity
    var minY: Float = Float.infinity
    var maxY: Float = -Float.infinity
    var minZ: Float = Float.infinity
    var maxZ: Float = -Float.infinity

    let vertices = self.vertices
    for i in 0..<numberOfVertices {
      let localPos = vec3(
        Float(vertices[i * 3 + 0]),
        Float(vertices[i * 3 + 1]),
        Float(vertices[i * 3 + 2])
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


