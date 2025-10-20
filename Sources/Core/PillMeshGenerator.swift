import GL
import GLMath

/// Generates a procedural pill (capsule) mesh
class PillMeshGenerator {

  /// Generate a pill mesh with specified dimensions
  static func generatePill(diameter: Float = 1.0, height: Float = 2.0, segments: Int = 16) -> (
    vertices: [Float], indices: [UInt32]
  ) {
    var vertices: [Float] = []
    var indices: [UInt32] = []

    let radius = diameter / 2.0
    let halfHeight = height / 2.0
    let cylinderHeight = height - diameter  // Height of the cylindrical part

    // Generate vertices for the pill
    var vertexIndex: UInt32 = 0

    // Top hemisphere
    for i in 0...segments {
      let lat = Float(i) * .pi / Float(segments) - .pi / 2
      for j in 0...segments {
        let lon = Float(j) * 2.0 * .pi / Float(segments)

        let x = radius * GLMath.cos(lat) * GLMath.cos(lon)
        let y = radius * GLMath.sin(lat) + halfHeight
        let z = radius * GLMath.cos(lat) * GLMath.sin(lon)

        // Position
        vertices.append(x)
        vertices.append(y)
        vertices.append(z)

        // Normal
        vertices.append(x / radius)
        vertices.append(y / radius)
        vertices.append(z / radius)

        // UV coordinates
        vertices.append(Float(j) / Float(segments))
        vertices.append(Float(i) / Float(segments))

        // Tangent (simplified)
        vertices.append(-GLMath.sin(lon))
        vertices.append(0)
        vertices.append(GLMath.cos(lon))

        // Bitangent (simplified)
        vertices.append(GLMath.cos(lat) * GLMath.sin(lon))
        vertices.append(-GLMath.sin(lat))
        vertices.append(GLMath.cos(lat) * GLMath.cos(lon))

        if i < segments && j < segments {
          let current = vertexIndex
          let next = vertexIndex + 1
          let below = vertexIndex + UInt32(segments + 1)
          let belowNext = vertexIndex + UInt32(segments + 1) + 1

          // First triangle
          indices.append(current)
          indices.append(below)
          indices.append(next)

          // Second triangle
          indices.append(next)
          indices.append(below)
          indices.append(belowNext)
        }

        vertexIndex += 1
      }
    }

    // Cylindrical middle section
    let cylinderStartIndex = vertexIndex
    for i in 0...1 {  // Top and bottom of cylinder
      let y = halfHeight - Float(i) * cylinderHeight
      for j in 0...segments {
        let angle = Float(j) * 2.0 * .pi / Float(segments)
        let x = radius * GLMath.cos(angle)
        let z = radius * GLMath.sin(angle)

        // Position
        vertices.append(x)
        vertices.append(y)
        vertices.append(z)

        // Normal (pointing outward)
        vertices.append(x / radius)
        vertices.append(0)
        vertices.append(z / radius)

        // UV coordinates
        vertices.append(Float(j) / Float(segments))
        vertices.append(Float(i))

        // Tangent
        vertices.append(-GLMath.sin(angle))
        vertices.append(0)
        vertices.append(GLMath.cos(angle))

        // Bitangent
        vertices.append(0)
        vertices.append(1)
        vertices.append(0)
      }
    }

    // Connect cylinder top and bottom
    for j in 0..<segments {
      let topCurrent = cylinderStartIndex + UInt32(j)
      let topNext = cylinderStartIndex + UInt32((j + 1) % (segments + 1))
      let bottomCurrent = cylinderStartIndex + UInt32(segments + 1) + UInt32(j)
      let bottomNext = cylinderStartIndex + UInt32(segments + 1) + UInt32((j + 1) % (segments + 1))

      // First triangle
      indices.append(topCurrent)
      indices.append(bottomCurrent)
      indices.append(topNext)

      // Second triangle
      indices.append(topNext)
      indices.append(bottomCurrent)
      indices.append(bottomNext)
    }

    // Bottom hemisphere
    //let bottomStartIndex = vertexIndex
    for i in 0...segments {
      let lat = Float(i) * .pi / Float(segments) - .pi / 2
      for j in 0...segments {
        let lon = Float(j) * 2.0 * .pi / Float(segments)

        let x = radius * GLMath.cos(lat) * GLMath.cos(lon)
        let y = radius * GLMath.sin(lat) - halfHeight
        let z = radius * GLMath.cos(lat) * GLMath.sin(lon)

        // Position
        vertices.append(x)
        vertices.append(y)
        vertices.append(z)

        // Normal
        vertices.append(x / radius)
        vertices.append(y / radius)
        vertices.append(z / radius)

        // UV coordinates
        vertices.append(Float(j) / Float(segments))
        vertices.append(1.0 - Float(i) / Float(segments))

        // Tangent
        vertices.append(-GLMath.sin(lon))
        vertices.append(0)
        vertices.append(GLMath.cos(lon))

        // Bitangent
        vertices.append(GLMath.cos(lat) * GLMath.sin(lon))
        vertices.append(-GLMath.sin(lat))
        vertices.append(GLMath.cos(lat) * GLMath.cos(lon))

        if i < segments && j < segments {
          let current = vertexIndex
          let next = vertexIndex + 1
          let below = vertexIndex + UInt32(segments + 1)
          let belowNext = vertexIndex + UInt32(segments + 1) + 1

          // First triangle
          indices.append(current)
          indices.append(next)
          indices.append(below)

          // Second triangle
          indices.append(next)
          indices.append(belowNext)
          indices.append(below)
        }

        vertexIndex += 1
      }
    }

    return (vertices, indices)
  }
}
