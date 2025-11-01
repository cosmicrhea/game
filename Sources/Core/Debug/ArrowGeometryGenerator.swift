/// Generates volumetric 3D debug arrow geometry
/// Based on Godot Debug Draw 3D arrow geometry implementation
class ArrowGeometryGenerator {

  /// Generate volumetric arrow geometry
  /// - Parameters:
  ///   - length: Total length of the arrow
  ///   - headLength: Length of the arrowhead (default: 10% of length)
  ///   - headRadius: Radius of the arrowhead base (default: 3% of length)
  ///   - shaftRadius: Radius of the arrow shaft (default: 1% of length)
  ///   - segments: Number of segments for cylindrical parts (default: 8)
  /// - Returns: Tuple of vertices (positions as Float array) and indices
  static func generateArrow(
    length: Float,
    headLength: Float? = nil,
    headRadius: Float? = nil,
    shaftRadius: Float? = nil,
    segments: Int = 8
  ) -> (vertices: [Float], indices: [UInt32]) {

    let defaultHeadLength = length * 0.1
    let defaultHeadRadius = length * 0.03
    let defaultShaftRadius = length * 0.01

    let actualHeadLength = headLength ?? defaultHeadLength
    let actualHeadRadius = headRadius ?? defaultHeadRadius
    let actualShaftRadius = shaftRadius ?? defaultShaftRadius
    let shaftLength = length - actualHeadLength

    var vertices: [Float] = []
    var indices: [UInt32] = []

    // Arrow points along +Z axis, starting at origin
    // Shaft goes from (0,0,0) to (0,0,shaftLength)
    // Head goes from (0,0,shaftLength) to (0,0,length), base radius at shaftLength

    var vertexIndex: UInt32 = 0

    // Generate shaft (cylinder from z=0 to z=shaftLength)
    if shaftLength > 0 {
      // Bottom circle of shaft
      for i in 0..<segments {
        let angle = Float(i) * 2.0 * .pi / Float(segments)
        let x = actualShaftRadius * GLMath.cos(angle)
        let y = actualShaftRadius * GLMath.sin(angle)
        let z: Float = 0

        // Position
        vertices.append(x)
        vertices.append(y)
        vertices.append(z)

        // Normal (pointing outward)
        vertices.append(GLMath.cos(angle))
        vertices.append(GLMath.sin(angle))
        vertices.append(0)

        // UV
        vertices.append(Float(i) / Float(segments))
        vertices.append(0)

        // Tangent
        vertices.append(-GLMath.sin(angle))
        vertices.append(GLMath.cos(angle))
        vertices.append(0)

        // Bitangent
        vertices.append(0)
        vertices.append(0)
        vertices.append(1)
      }

      // Top circle of shaft
      for i in 0..<segments {
        let angle = Float(i) * 2.0 * .pi / Float(segments)
        let x = actualShaftRadius * GLMath.cos(angle)
        let y = actualShaftRadius * GLMath.sin(angle)
        let z = shaftLength

        // Position
        vertices.append(x)
        vertices.append(y)
        vertices.append(z)

        // Normal (pointing outward)
        vertices.append(GLMath.cos(angle))
        vertices.append(GLMath.sin(angle))
        vertices.append(0)

        // UV
        vertices.append(Float(i) / Float(segments))
        vertices.append(1)

        // Tangent
        vertices.append(-GLMath.sin(angle))
        vertices.append(GLMath.cos(angle))
        vertices.append(0)

        // Bitangent
        vertices.append(0)
        vertices.append(0)
        vertices.append(1)
      }

      // Connect shaft top and bottom with quads
      let shaftBottomStart = vertexIndex
      let shaftTopStart = vertexIndex + UInt32(segments)

      for i in 0..<segments {
        let current = i
        let next = (i + 1) % segments

        let bottomCurrent = shaftBottomStart + UInt32(current)
        let bottomNext = shaftBottomStart + UInt32(next)
        let topCurrent = shaftTopStart + UInt32(current)
        let topNext = shaftTopStart + UInt32(next)

        // First triangle
        indices.append(bottomCurrent)
        indices.append(topCurrent)
        indices.append(bottomNext)

        // Second triangle
        indices.append(bottomNext)
        indices.append(topCurrent)
        indices.append(topNext)
      }

      vertexIndex += UInt32(segments * 2)
    }

    // Generate arrowhead (cone from z=shaftLength to z=length)
    let headBottomZ = shaftLength
    let headTopZ = length

    // Bottom circle of head (at z=shaftLength, radius=headRadius)
    var headBottomStart = vertexIndex
    for i in 0..<segments {
      let angle = Float(i) * 2.0 * .pi / Float(segments)
      let x = actualHeadRadius * GLMath.cos(angle)
      let y = actualHeadRadius * GLMath.sin(angle)
      let z = headBottomZ

      // Position
      vertices.append(x)
      vertices.append(y)
      vertices.append(z)

      // Normal (pointing outward and slightly up)
      let normalAngle = atan2(actualHeadLength, actualHeadRadius)
      vertices.append(GLMath.cos(angle) * GLMath.cos(normalAngle))
      vertices.append(GLMath.sin(angle) * GLMath.cos(normalAngle))
      vertices.append(GLMath.sin(normalAngle))

      // UV
      vertices.append(Float(i) / Float(segments))
      vertices.append(0)

      // Tangent
      vertices.append(-GLMath.sin(angle))
      vertices.append(GLMath.cos(angle))
      vertices.append(0)

      // Bitangent
      vertices.append(GLMath.cos(angle) * GLMath.sin(normalAngle))
      vertices.append(GLMath.sin(angle) * GLMath.sin(normalAngle))
      vertices.append(-GLMath.cos(normalAngle))
    }

    // Tip of arrowhead (at z=length, single point)
    let tipIndex = vertexIndex + UInt32(segments)
    vertices.append(0)
    vertices.append(0)
    vertices.append(headTopZ)

    // Normal at tip points upward
    vertices.append(0)
    vertices.append(0)
    vertices.append(1)

    // UV
    vertices.append(0.5)
    vertices.append(1)

    // Tangent
    vertices.append(1)
    vertices.append(0)
    vertices.append(0)

    // Bitangent
    vertices.append(0)
    vertices.append(1)
    vertices.append(0)

    // Connect head bottom to tip
    headBottomStart = vertexIndex
    for i in 0..<segments {
      let current = i
      let next = (i + 1) % segments

      let bottomCurrent = headBottomStart + UInt32(current)
      let bottomNext = headBottomStart + UInt32(next)

      // Triangle from bottom edge to tip
      indices.append(bottomCurrent)
      indices.append(tipIndex)
      indices.append(bottomNext)
    }

    // Close the bottom of head if it's separate from shaft
    if shaftLength > 0 {
      // Add bottom face of head
      for i in 1..<(segments - 1) {
        let current = headBottomStart + UInt32(i)
        let next = headBottomStart + UInt32(i + 1)

        indices.append(headBottomStart)
        indices.append(next)
        indices.append(current)
      }
    }

    return (vertices, indices)
  }

  /// Generate wireframe arrow geometry (lines only)
  /// Based on Godot Debug Draw 3D simplified arrow indices
  /// - Parameters:
  ///   - length: Total length of the arrow
  ///   - headLength: Length of the arrowhead
  ///   - headRadius: Radius of the arrowhead base
  ///   - lineThickness: Thickness multiplier for the arrow (default: 1.0)
  /// - Returns: Tuple of vertices (positions as vec3 array) and indices for lines
  static func generateWireframeArrow(
    length: Float,
    headLength: Float? = nil,
    headRadius: Float? = nil,
    lineThickness: Float = 1.0
  ) -> (vertices: [vec3], indices: [UInt32]) {

    let defaultHeadLength = length * 0.1
    let defaultHeadRadius = length * 0.03

    let actualHeadLength = headLength ?? defaultHeadLength
    let actualHeadRadius = (headRadius ?? defaultHeadRadius) * lineThickness
    let shaftLength = length - actualHeadLength

    var vertices: [vec3] = []
    var indices: [UInt32] = []

    // Arrow points along +Z axis
    // Tip at (0,0,length)
    // Head base at (0,0,shaftLength)
    // Shaft start at (0,0,0)

    var vertexIndex: UInt32 = 0

    // Tip point
    let tipIndex = vertexIndex
    vertices.append(vec3(0, 0, length))
    vertexIndex += 1

    // Arrowhead base vertices (4 vertices in cross pattern)
    let headBaseZ = shaftLength
    let headBaseVertices: [UInt32] = [
      vertexIndex,  // +Y
      vertexIndex + 1,  // -Y
      vertexIndex + 2,  // +X
      vertexIndex + 3,  // -X
    ]

    vertices.append(vec3(0, actualHeadRadius, headBaseZ))  // +Y
    vertices.append(vec3(0, -actualHeadRadius, headBaseZ))  // -Y
    vertices.append(vec3(actualHeadRadius, 0, headBaseZ))  // +X
    vertices.append(vec3(-actualHeadRadius, 0, headBaseZ))  // -X
    vertexIndex += 4

    // Connect tip to head base vertices
    for baseVertex in headBaseVertices {
      indices.append(tipIndex)
      indices.append(baseVertex)
    }

    // Connect head base vertices in cross pattern
    indices.append(headBaseVertices[0])  // +Y
    indices.append(headBaseVertices[1])  // -Y
    indices.append(headBaseVertices[2])  // +X
    indices.append(headBaseVertices[3])  // -X

    // Shaft - make it visible with thickness
    if shaftLength > 0 {
      let shaftRadius = length * 0.01 * lineThickness  // Shaft radius proportional to arrow length

      // Add shaft vertices in cross pattern at start and end
      let shaftStartVertices: [UInt32] = [
        vertexIndex,  // +Y at start
        vertexIndex + 1,  // -Y at start
        vertexIndex + 2,  // +X at start
        vertexIndex + 3,  // -X at start
      ]

      vertices.append(vec3(0, shaftRadius, 0))  // +Y at start
      vertices.append(vec3(0, -shaftRadius, 0))  // -Y at start
      vertices.append(vec3(shaftRadius, 0, 0))  // +X at start
      vertices.append(vec3(-shaftRadius, 0, 0))  // -X at start
      vertexIndex += 4

      let shaftEndVertices: [UInt32] = [
        vertexIndex,  // +Y at end
        vertexIndex + 1,  // -Y at end
        vertexIndex + 2,  // +X at end
        vertexIndex + 3,  // -X at end
      ]

      vertices.append(vec3(0, shaftRadius, headBaseZ))  // +Y at end
      vertices.append(vec3(0, -shaftRadius, headBaseZ))  // -Y at end
      vertices.append(vec3(shaftRadius, 0, headBaseZ))  // +X at end
      vertices.append(vec3(-shaftRadius, 0, headBaseZ))  // -X at end
      vertexIndex += 4

      // Connect shaft start to end (main line down center)
      indices.append(shaftStartVertices[0])  // +Y start
      indices.append(shaftEndVertices[0])  // +Y end
      indices.append(shaftStartVertices[1])  // -Y start
      indices.append(shaftEndVertices[1])  // -Y end
      indices.append(shaftStartVertices[2])  // +X start
      indices.append(shaftEndVertices[2])  // +X end
      indices.append(shaftStartVertices[3])  // -X start
      indices.append(shaftEndVertices[3])  // -X end

      // Connect shaft vertices in cross pattern at start
      indices.append(shaftStartVertices[0])  // +Y
      indices.append(shaftStartVertices[1])  // -Y
      indices.append(shaftStartVertices[2])  // +X
      indices.append(shaftStartVertices[3])  // -X

      // Connect shaft vertices in cross pattern at end
      indices.append(shaftEndVertices[0])  // +Y
      indices.append(shaftEndVertices[1])  // -Y
      indices.append(shaftEndVertices[2])  // +X
      indices.append(shaftEndVertices[3])  // -X
    }

    return (vertices, indices)
  }
}
