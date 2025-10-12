import Assimp
import GL

class MeshInstance {
  struct Vertex {
    var position: (AssimpReal, AssimpReal, AssimpReal)
    var normal: (AssimpReal, AssimpReal, AssimpReal)
    var uv: (AssimpReal, AssimpReal)
  }

  let scene: Scene
  let mesh: Mesh

  var VAO: GLuint = 0
  var VBO: GLuint = 0
  var EBO: GLuint = 0

  init(scene: Scene, mesh: Mesh) {
    self.scene = scene
    self.mesh = mesh

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
