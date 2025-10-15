import Assimp
import GL
import GLMath

class MeshInstance {
  struct Vertex {
    var position: (AssimpReal, AssimpReal, AssimpReal)
    var normal: (AssimpReal, AssimpReal, AssimpReal)
    var uv: (AssimpReal, AssimpReal)
  }

  let scene: Scene
  let mesh: Mesh
  let transformMatrix: mat4

  var VAO: GLuint = 0
  var VBO: GLuint = 0
  var EBO: GLuint = 0

  init(scene: Scene, mesh: Mesh, transformMatrix: mat4 = mat4(1)) {
    self.scene = scene
    self.mesh = mesh
    self.transformMatrix = transformMatrix

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
      0, 3, GL_FLOAT, false, GLsizei(MemoryLayout<Vertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \Vertex.position)!))

    // vertex normals
    glEnableVertexAttribArray(1)
    glVertexAttribPointer(
      1, 3, GL_FLOAT, false, GLsizei(MemoryLayout<Vertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \Vertex.normal)!))

    // vertex texture coords
    glEnableVertexAttribArray(2)
    glVertexAttribPointer(
      2, 2, GL_FLOAT, false, GLsizei(MemoryLayout<Vertex>.stride),
      UnsafeRawPointer(bitPattern: MemoryLayout.offset(of: \Vertex.uv)!))

    glBindVertexArray(0)
  }

  func draw() {
    //        let material = scene.materials[mesh.materialIndex]
    //        material.getMaterialTexture(texType: .baseColor, texIndex: 0)
    //        glActiveTextureARB(texture: GL_TEXTURE0)
    //        glBindTexture(GL_TEXTURE_2D)

    glBindVertexArray(VAO)
    glDrawElements(GL_TRIANGLES, GLsizei(mesh.faces.count * 3), GL_UNSIGNED_INT, nil)
    glBindVertexArray(0)
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
  func makeVertices() -> [MeshInstance.Vertex] {
    let positions = vertices
    let normals = self.normals
    let uvs = texCoordsPacked.0

    var result: [MeshInstance.Vertex] = []
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
      result.append(MeshInstance.Vertex(position: p, normal: n, uv: t))
    }
    return result
  }

  func makeIndices32() -> [UInt32] {
    faces.flatMap { face in face.indices.map { UInt32($0) } }
  }
}
