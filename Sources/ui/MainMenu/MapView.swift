import Assimp
import Foundation
import GLMath

@Editable  //(.grouped)
class MapView: RenderLoop {

  private var mapEffect = GLScreenEffect("Common/MapView")
  private var scene: Scene?
  private let promptList = PromptList(.mapView)

  // Map shader program
  private var mapShaderProgram: GLProgram?

  // Mesh instances for rendering
  private var floorMeshInstances: [MeshInstance] = []
  private var doorMeshInstances: [MeshInstance] = []
  // Border line data for room outlines (GL_LINES)
  private struct BorderLineData {
    var vertices: [Float]  // x, y, z per vertex
    var indices: [UInt32]  // pairs of indices for lines
    var VAO: GLuint
    var VBO: GLuint
    var EBO: GLuint
  }
  private var borderLineMeshes: [BorderLineData] = []
  // Store border segments for door alignment (start, end points in world space)
  private var borderSegments: [(start: vec3, end: vec3)] = []

  // Area (room) data for labels
  private var areaData: [(node: Node, floorNode: Node?, boundingBox: (min: vec3, max: vec3))] = []

  // Door-to-area relationships: maps door index to array of area indices it connects
  private var doorToAreas: [Int: [Int]] = [:]
  // Adjusted transforms for doors (aligned to walls)
  private var doorAdjustedTransforms: [Int: mat4] = [:]

  // Room visibility mask for debugging (binary: each bit represents a room)
  private var roomVisibilityMask: UInt = 0  // 0 = all visible, or use bitmask
  private var roomVisibilityMode: RoomVisibilityMode = .all

  // Setup flag
  private var isSetupComplete = false

  enum RoomVisibilityMode {
    case all  // Show all rooms
    case binary(UInt)  // Binary mask: bit N = room N visible
  }

  // Camera from scene
  private var debugCamera: Assimp.Camera?
  private var debugCameraNode: Node?
  private var debugCameraWorldTransform: mat4 = mat4(1)

  // Camera controls
  private var cameraPan: vec2 = vec2(0, 0)  // Pan offset in world space
  private var cameraZoom: Float = 0.8  // Zoom level (1.0 = default)
  private var baseSceneBounds: (minX: Float, maxX: Float, minZ: Float, maxZ: Float)? = nil

  // Mouse drag panning
  private var isDragging = false
  private var lastMousePos: Point = Point(0, 0)

  // Reset animation
  private var isResetting: Bool = false
  private var resetStartTime: Float = 0.0
  private let resetDuration: Float = 1.0
  private var resetStartPan: vec2 = vec2(0, 0)
  private var resetStartZoom: Float = 0.8

  @Editor(8.0...64.0) var gridCellSize: Float = 32.0
  @Editor(0.5...3.0) var gridThickness: Float = 1.0
  @Editor(0.1...3.0) var gridScale: Float = 1.0
  @Editor var gridOpacity: Float = 0.1

  @Editor var vignetteStrength: Float = 0.7
  @Editor var vignetteRadius: Float = 1.0

  // SDF edge detection parameters
  @Editor(0.01...50.0) var sdfGradientScale: Float = 4.89
  @Editor(0.001...1.0) var sdfEpsilon: Float = 0.26
  @Editor(0.0...20.0) var sdfDistanceOffset: Float = 10.00
  @Editor(0.1...100.0) var sdfDistanceMultiplier: Float = 0.39
  @Editor(0.0...5.0) var strokeThreshold: Float = 0.98
  @Editor(0.0...5.0) var shadowThreshold: Float = 0.0
  @Editor(0.0...100.0) var shadowSize: Float = 30.0  // Inner glow/shadow size in pixels
  @Editor(0.0...50.0) var strokeWidth: Float = 5.12  // Stroke width in pixels
  @Editor(0.0...1.0) var shadowStrength: Float = 0.25  // Inner shadow strength (0-1)
  @Editor(0.5...5.0) var shadowFalloff: Float = 2.04  // Inner shadow falloff power (higher = softer)
  @Editor var debugShowGradient: Bool = false  // Visualize gradient instead of stroke
  @Editor var enableWallMerging: Bool = true  // Toggle wall merging

  var backgroundColor: Color = .blueprintBackground
  var gridColor: Color = .blueprintGrid

  init() {
    // Initialize map shader
    do {
      mapShaderProgram = try GLProgram("Common/mapMesh", "Common/mapMesh")
    } catch {
      print("Failed to load map shader: \(error)")
    }

    Task {
      do {
        let scenePath = Bundle.game.path(forResource: "Scenes/shooting_range", ofType: "glb")!
        let assimpScene = try Assimp.Scene(
          file: scenePath,
          flags: [.triangulate, .flipUVs, .calcTangentSpace]
        )
        await MainActor.run {
          self.scene = Scene(assimpScene)
        }
      } catch {
        print("Failed to load scene: \(error)")
      }
    }
  }

  private func setupMapRendering() {
    guard let scene = scene else { return }

    // DEBUG: Print all metadata keys from all nodes
    printAllMetadataKeys(in: scene.rootNode, indent: 0)

    // Find and set up Camera_0 (debug/orthographic camera)
    if let cameraNode = scene.rootNode.findNode(named: "Camera_0") {
      debugCameraNode = cameraNode
      debugCameraWorldTransform = calculateNodeWorldTransform(cameraNode, in: scene)
      print("✅ Found Camera_0 node")
    }

    if let camera = scene.cameras.first(where: { $0.name == "Camera_0" }) {
      debugCamera = camera
      print(
        "✅ Found Camera_0: orthoWidth=\(camera.orthographicWidth), aspect=\(camera.aspect), near=\(camera.clipPlaneNear), far=\(camera.clipPlaneFar)"
      )
    } else {
      print("⚠️ Camera_0 not found in scene cameras")
    }

    // Find floor nodes (children of room nodes)
    let floorNodes = findNodesContaining(keywords: ["Floor"], in: scene.rootNode)

    // Find door action nodes (under Actions)
    let doorActionNodes = findNodesContaining(keywords: ["Door-action", "FrontDoor-action"], in: scene.rootNode)

    // Find actual area (room) nodes (exclude parent "Rooms" node - only get nodes that end with "-col" or are children)
    let allAreaNodes = findNodesContaining(keywords: ["Room"], in: scene.rootNode)
    let areaNodes = allAreaNodes.filter { node in
      // Only include nodes that are actual areas (have "-col" suffix or are children of Rooms)
      if let name = node.name {
        return name.contains("-col") || name == "HallwayRoom-col" || name == "ShootingRangeRoom-col"
      }
      return false
    }

    // Store area data for labels (only actual area nodes)
    for node in areaNodes {
      let worldTransform = calculateNodeWorldTransform(node, in: scene)
      let boundingBox = calculateNodeBoundingBox(node, transform: worldTransform, in: scene)

      // Find the Floor node within this area node's children
      let floorNode = findFloorNode(in: node)
      areaData.append((node: node, floorNode: floorNode, boundingBox: boundingBox))
    }

    // Create mesh instances for floors
    for node in floorNodes {
      let worldTransform = calculateNodeWorldTransform(node, in: scene)
      for meshIndex in node.meshes {
        guard meshIndex < scene.meshes.count else { continue }
        let mesh = scene.meshes[Int(meshIndex)]
        guard mesh.numberOfVertices > 0 else { continue }

        let meshInstance = MeshInstance(
          scene: scene,
          mesh: mesh,
          transformMatrix: worldTransform,
          sceneIdentifier: scene.filePath
        )
        meshInstance.node = node
        floorMeshInstances.append(meshInstance)
        if let border = createBorderLineMesh(from: meshInstance) {
          borderLineMeshes.append(border)
        }
      }
    }

    // Create mesh instances for door actions
    for node in doorActionNodes {
      let worldTransform = calculateNodeWorldTransform(node, in: scene)
      for meshIndex in node.meshes {
        guard meshIndex < scene.meshes.count else { continue }
        let mesh = scene.meshes[Int(meshIndex)]
        guard mesh.numberOfVertices > 0 else { continue }

        let meshInstance = MeshInstance(
          scene: scene,
          mesh: mesh,
          transformMatrix: worldTransform,
          sceneIdentifier: scene.filePath
        )
        meshInstance.node = node
        doorMeshInstances.append(meshInstance)
      }
    }

    // Merge overlapping wall segments (where two rooms share a wall)
    if enableWallMerging {
      mergeOverlappingWallSegments()
    }

    // Calculate door-to-area relationships
    calculateDoorToAreaRelationships()

    // Align doors to walls
    alignDoorsToWalls()

    // Calculate and store base scene bounds for camera
    calculateBaseSceneBounds()
  }

  /// Merge overlapping wall segments where two rooms share a wall
  private func mergeOverlappingWallSegments() {
    guard borderSegments.count > 1 else { return }

    let threshold: Float = 0.15  // Distance threshold for considering segments as overlapping

    // Helper to check if two points are very close (in XZ plane)
    func pointsAreClose(_ a: vec3, _ b: vec3) -> Bool {
      let dx = a.x - b.x
      let dz = a.z - b.z
      return sqrt(dx * dx + dz * dz) < threshold
    }

    // Helper to check if two segments are the same (or reversed)
    func segmentsAreSame(_ seg1: (start: vec3, end: vec3), _ seg2: (start: vec3, end: vec3)) -> Bool {
      // Check if they're the same direction
      if pointsAreClose(seg1.start, seg2.start) && pointsAreClose(seg1.end, seg2.end) {
        return true
      }
      // Check if they're reversed
      if pointsAreClose(seg1.start, seg2.end) && pointsAreClose(seg1.end, seg2.start) {
        return true
      }
      return false
    }

    // Build list of unique segments
    var uniqueSegments: [(start: vec3, end: vec3)] = []
    var processedIndices = Set<Int>()

    for (i, segment) in borderSegments.enumerated() {
      if processedIndices.contains(i) { continue }

      // Check if this segment matches any already in uniqueSegments
      var isDuplicate = false
      for uniqueSegment in uniqueSegments {
        if segmentsAreSame(segment, uniqueSegment) {
          isDuplicate = true
          break
        }
      }

      if !isDuplicate {
        uniqueSegments.append(segment)
        processedIndices.insert(i)

        // Also mark any other segments that match this one
        for (j, otherSegment) in borderSegments.enumerated() {
          if j != i && !processedIndices.contains(j) {
            if segmentsAreSame(segment, otherSegment) {
              processedIndices.insert(j)
            }
          }
        }
      }
    }

    let originalCount = borderSegments.count
    // Replace border segments with deduplicated list
    borderSegments = uniqueSegments

    print("Merged overlapping walls: \(uniqueSegments.count) unique segments (was \(originalCount))")

    // Regenerate border line meshes from merged segments
    regenerateBorderLineMeshes()
  }

  /// Regenerate border line meshes from the merged border segments
  private func regenerateBorderLineMeshes() {
    // Clean up old meshes
    for border in borderLineMeshes {
      var vao = border.VAO
      var vbo = border.VBO
      var ebo = border.EBO
      glDeleteVertexArrays(1, &vao)
      glDeleteBuffers(1, &vbo)
      glDeleteBuffers(1, &ebo)
    }
    borderLineMeshes.removeAll()

    // Create new mesh from merged segments
    guard !borderSegments.isEmpty else { return }

    let lineWidth: Float = 0.1  // World units - thick border
    var quadVertices: [Float] = []
    var quadIndices: [UInt32] = []
    var vertexIndex: UInt32 = 0

    for segment in borderSegments {
      let start = segment.start
      let end = segment.end

      // Calculate line direction in XZ plane (Y is up)
      let direction = vec3(end.x - start.x, 0, end.z - start.z)
      let length = sqrt(direction.x * direction.x + direction.z * direction.z)
      guard length > 0.001 else { continue }

      // Normalized direction
      let dir = vec3(direction.x / length, 0, direction.z / length)

      // Perpendicular vector in XZ plane (for line width)
      let perp = vec3(-dir.z * lineWidth, 0, dir.x * lineWidth)

      // Extend line ends by full width to ensure caps fully meet and overlap
      let extendedStart = vec3(start.x - dir.x * lineWidth, start.y, start.z - dir.z * lineWidth)
      let extendedEnd = vec3(end.x + dir.x * lineWidth, end.y, end.z + dir.z * lineWidth)

      // Elevate well above floor so walls render on top of floor inner shadows
      let yOffset: Float = 0.05

      // Create quad vertices (4 vertices = 2 triangles)
      let v0 = vec3(extendedStart.x + perp.x, extendedStart.y + yOffset, extendedStart.z + perp.z)
      let v1 = vec3(extendedStart.x - perp.x, extendedStart.y + yOffset, extendedStart.z - perp.z)
      let v2 = vec3(extendedEnd.x + perp.x, extendedEnd.y + yOffset, extendedEnd.z + perp.z)
      let v3 = vec3(extendedEnd.x - perp.x, extendedEnd.y + yOffset, extendedEnd.z - perp.z)

      // Add vertices
      let baseIndex = vertexIndex
      quadVertices.append(contentsOf: [v0.x, v0.y, v0.z])
      quadVertices.append(contentsOf: [v1.x, v1.y, v1.z])
      quadVertices.append(contentsOf: [v2.x, v2.y, v2.z])
      quadVertices.append(contentsOf: [v3.x, v3.y, v3.z])

      // Add triangle indices (two triangles per quad)
      quadIndices.append(contentsOf: [
        baseIndex, baseIndex + 1, baseIndex + 2,  // First triangle
        baseIndex + 1, baseIndex + 3, baseIndex + 2,  // Second triangle
      ])

      vertexIndex += 4
    }

    if quadVertices.isEmpty || quadIndices.isEmpty { return }

    // Create OpenGL buffers
    var VAO: GLuint = 0
    var VBO: GLuint = 0
    var EBO: GLuint = 0

    glGenVertexArrays(1, &VAO)
    glGenBuffers(1, &VBO)
    glGenBuffers(1, &EBO)

    glBindVertexArray(VAO)

    // Upload vertex data
    glBindBuffer(GL_ARRAY_BUFFER, VBO)
    quadVertices.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    // Upload index data
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO)
    quadIndices.withUnsafeBytes { bytes in
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    // Set vertex attributes (position only for quads)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)

    // Disable other attributes (normals, texcoords) - not needed for border quads
    glDisableVertexAttribArray(1)
    glDisableVertexAttribArray(2)

    glBindVertexArray(0)

    // Add single merged mesh
    borderLineMeshes.append(
      BorderLineData(
        vertices: quadVertices,
        indices: quadIndices,
        VAO: VAO,
        VBO: VBO,
        EBO: EBO
      ))
  }

  /// Align doors to nearest wall edges
  private func alignDoorsToWalls() {
    guard !borderSegments.isEmpty else { return }

    for (doorIndex, doorInstance) in doorMeshInstances.enumerated() {
      // Get door's current center position
      let doorBounds = calculateMeshBoundingBox(mesh: doorInstance.mesh, transform: doorInstance.transformMatrix)
      let doorCenter = vec3(
        (doorBounds.min.x + doorBounds.max.x) * 0.5,
        (doorBounds.min.y + doorBounds.max.y) * 0.5,
        (doorBounds.min.z + doorBounds.max.z) * 0.5
      )

      // Find nearest border segment
      var nearestSegment: (start: vec3, end: vec3)? = nil
      var minDistance: Float = Float.infinity
      var nearestPointOnSegment: vec3 = doorCenter

      for segment in borderSegments {
        // Project door center onto line segment
        let segStart = segment.start
        let segEnd = segment.end
        let segDir = segEnd - segStart
        let segLengthSq = dot(segDir, segDir)

        guard segLengthSq > 0.001 else { continue }

        // Project point onto line
        let toPoint = doorCenter - segStart
        let t = dot(toPoint, segDir) / segLengthSq
        let clampedT = max(0.0, min(1.0, t))  // Clamp to segment
        let projectedPoint = segStart + segDir * clampedT

        // Calculate distance in XZ plane (ignore Y)
        let dx = doorCenter.x - projectedPoint.x
        let dz = doorCenter.z - projectedPoint.z
        let distance = sqrt(dx * dx + dz * dz)

        if distance < minDistance {
          minDistance = distance
          nearestSegment = segment
          nearestPointOnSegment = projectedPoint
        }
      }

      guard let segment = nearestSegment, minDistance < 1.0 else { continue }  // Only align if within 1 unit

      // Calculate alignment: move door center to projected point on wall
      let segDir = segment.end - segment.start
      let segLength = length(segDir)
      guard segLength > 0.001 else { continue }

      let segDirNormalized = segDir / segLength

      // Calculate door's current size (approximate from bounding box)
      let doorSize = vec3(
        doorBounds.max.x - doorBounds.min.x,
        doorBounds.max.y - doorBounds.min.y,
        doorBounds.max.z - doorBounds.min.z
      )

      // Determine door's depth (smallest dimension is usually depth)
      let doorDepth = min(doorSize.x, doorSize.z)

      // Move door so its center aligns with the wall edge
      // The door should be positioned so it's flush with the wall
      var newTransform = doorInstance.transformMatrix
      let currentCenter = vec3(newTransform[3][0], newTransform[3][1], newTransform[3][2])

      // Calculate offset: move door center to projected point
      let offset = nearestPointOnSegment - currentCenter

      // Apply offset (only X and Z, keep Y)
      newTransform[3][0] += offset.x
      newTransform[3][2] += offset.z

      // Store adjusted transform
      doorAdjustedTransforms[doorIndex] = newTransform
    }
  }

  /// Calculate which areas (rooms) each door connects to based on spatial proximity
  private func calculateDoorToAreaRelationships() {
    doorToAreas.removeAll()

    // Calculate bounding boxes for all doors
    var doorBoundingBoxes: [(min: vec3, max: vec3)] = []
    for meshInstance in doorMeshInstances {
      let transform = meshInstance.transformMatrix
      let boundingBox = calculateMeshBoundingBox(mesh: meshInstance.mesh, transform: transform)
      doorBoundingBoxes.append(boundingBox)
    }

    // For each door, find which areas it overlaps or is near
    for (doorIndex, doorBounds) in doorBoundingBoxes.enumerated() {
      var connectedAreas: [Int] = []

      // Check each area
      for (areaIndex, (_, _, areaBounds)) in areaData.enumerated() {
        // Check if door overlaps or is very close to area (within threshold)
        let threshold: Float = 0.25  // 0.25 world units threshold for "near"

        // Expand area bounds by threshold
        let expandedAreaMin = areaBounds.min - vec3(threshold, threshold, threshold)
        let expandedAreaMax = areaBounds.max + vec3(threshold, threshold, threshold)

        // Check if door bounding box intersects expanded area bounds
        let intersects =
          doorBounds.max.x >= expandedAreaMin.x && doorBounds.min.x <= expandedAreaMax.x
          && doorBounds.max.y >= expandedAreaMin.y && doorBounds.min.y <= expandedAreaMax.y
          && doorBounds.max.z >= expandedAreaMin.z && doorBounds.min.z <= expandedAreaMax.z

        if intersects {
          connectedAreas.append(areaIndex)
        }
      }

      // Store relationship (even if empty - door might not connect to any area)
      if !connectedAreas.isEmpty {
        doorToAreas[doorIndex] = connectedAreas
      }
    }

    // Debug output
    print("Door-to-area relationships:")
    for (doorIndex, areas) in doorToAreas.sorted(by: { $0.key < $1.key }) {
      let areaNames = areas.map { "Area \($0 + 1)" }.joined(separator: ", ")
      print("  Door \(doorIndex + 1) connects to: \(areaNames)")
    }
  }

  /// Create thick border line mesh (quads/triangles) from a floor mesh
  private func createBorderLineMesh(from floor: MeshInstance) -> BorderLineData? {
    let mesh = floor.mesh
    let transform = floor.transformMatrix
    let lineWidth: Float = 0.1  // World units - thick border

    // Find unique edges (edges that appear only once are border edges)
    var edgeCount: [String: Int] = [:]

    func edgeKey(_ a: UInt32, _ b: UInt32) -> String {
      let minIdx = min(a, b)
      let maxIdx = max(a, b)
      return "\(minIdx)-\(maxIdx)"
    }

    // Count edges from all faces
    for face in mesh.faces {
      guard face.indices.count >= 3 else { continue }
      edgeCount[edgeKey(face.indices[0], face.indices[1]), default: 0] += 1
      edgeCount[edgeKey(face.indices[1], face.indices[2]), default: 0] += 1
      edgeCount[edgeKey(face.indices[2], face.indices[0]), default: 0] += 1
    }

    // Collect border edges as line segments (local to this function)
    var localBorderSegments: [(vec3, vec3)] = []

    // Add border edges
    for face in mesh.faces {
      guard face.indices.count >= 3 else { continue }
      let edges = [
        (face.indices[0], face.indices[1]),
        (face.indices[1], face.indices[2]),
        (face.indices[2], face.indices[0]),
      ]

      for (a, b) in edges {
        if edgeCount[edgeKey(a, b)] == 1 {
          // This is a border edge
          let baseA = Int(a) * 3
          let baseB = Int(b) * 3

          let localA = vec3(
            Float(mesh.vertices[baseA]),
            Float(mesh.vertices[baseA + 1]),
            Float(mesh.vertices[baseA + 2])
          )
          let localB = vec3(
            Float(mesh.vertices[baseB]),
            Float(mesh.vertices[baseB + 1]),
            Float(mesh.vertices[baseB + 2])
          )

          let worldA = transform * vec4(localA.x, localA.y, localA.z, 1.0)
          let worldB = transform * vec4(localB.x, localB.y, localB.z, 1.0)

          let segmentStart = vec3(worldA.x, worldA.y, worldA.z)
          let segmentEnd = vec3(worldB.x, worldB.y, worldB.z)
          localBorderSegments.append((segmentStart, segmentEnd))
        }
      }
    }

    if localBorderSegments.isEmpty { return nil }

    // Store segments in class-level array for door alignment
    for (start, end) in localBorderSegments {
      borderSegments.append((start: start, end: end))
    }

    // Convert line segments to thick quad geometry
    var quadVertices: [Float] = []
    var quadIndices: [UInt32] = []
    var vertexIndex: UInt32 = 0

    for (start, end) in localBorderSegments {
      // Calculate line direction in XZ plane (Y is up)
      let direction = vec3(end.x - start.x, 0, end.z - start.z)
      let length = sqrt(direction.x * direction.x + direction.z * direction.z)
      guard length > 0.001 else { continue }

      // Normalized direction
      let dir = vec3(direction.x / length, 0, direction.z / length)

      // Perpendicular vector in XZ plane (for line width)
      let perp = vec3(-dir.z * lineWidth, 0, dir.x * lineWidth)

      // Extend line ends by full width to ensure caps fully meet and overlap
      let extendedStart = vec3(start.x - dir.x * lineWidth, start.y, start.z - dir.z * lineWidth)
      let extendedEnd = vec3(end.x + dir.x * lineWidth, end.y, end.z + dir.z * lineWidth)

      // Elevate well above floor so walls render on top of floor inner shadows
      let yOffset: Float = 0.05

      // Create quad vertices (4 vertices = 2 triangles)
      // Quad is perpendicular to the line in XZ plane, slightly elevated
      let v0 = vec3(extendedStart.x + perp.x, extendedStart.y + yOffset, extendedStart.z + perp.z)
      let v1 = vec3(extendedStart.x - perp.x, extendedStart.y + yOffset, extendedStart.z - perp.z)
      let v2 = vec3(extendedEnd.x + perp.x, extendedEnd.y + yOffset, extendedEnd.z + perp.z)
      let v3 = vec3(extendedEnd.x - perp.x, extendedEnd.y + yOffset, extendedEnd.z - perp.z)

      // Add vertices
      let baseIndex = vertexIndex
      quadVertices.append(contentsOf: [v0.x, v0.y, v0.z])
      quadVertices.append(contentsOf: [v1.x, v1.y, v1.z])
      quadVertices.append(contentsOf: [v2.x, v2.y, v2.z])
      quadVertices.append(contentsOf: [v3.x, v3.y, v3.z])

      // Add triangle indices (two triangles per quad)
      quadIndices.append(contentsOf: [
        baseIndex, baseIndex + 1, baseIndex + 2,  // First triangle
        baseIndex + 1, baseIndex + 3, baseIndex + 2,  // Second triangle
      ])

      vertexIndex += 4
    }

    if quadVertices.isEmpty || quadIndices.isEmpty { return nil }

    // Create OpenGL buffers
    var VAO: GLuint = 0
    var VBO: GLuint = 0
    var EBO: GLuint = 0

    glGenVertexArrays(1, &VAO)
    glGenBuffers(1, &VBO)
    glGenBuffers(1, &EBO)

    glBindVertexArray(VAO)

    // Upload vertex data
    glBindBuffer(GL_ARRAY_BUFFER, VBO)
    quadVertices.withUnsafeBytes { bytes in
      glBufferData(GL_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    // Upload index data
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO)
    quadIndices.withUnsafeBytes { bytes in
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, bytes.count, bytes.baseAddress, GL_STATIC_DRAW)
    }

    // Set vertex attributes (position only for quads)
    glEnableVertexAttribArray(0)
    glVertexAttribPointer(0, 3, GL_FLOAT, false, GLsizei(3 * MemoryLayout<Float>.stride), nil)

    // Disable other attributes (normals, texcoords) - not needed for border quads
    glDisableVertexAttribArray(1)
    glDisableVertexAttribArray(2)

    glBindVertexArray(0)

    return BorderLineData(
      vertices: quadVertices,
      indices: quadIndices,
      VAO: VAO,
      VBO: VBO,
      EBO: EBO
    )
  }

  /// Calculate bounding box for a mesh with a transform
  private func calculateMeshBoundingBox(mesh: Assimp.Mesh, transform: mat4) -> (min: vec3, max: vec3) {
    var minX: Float = Float.infinity
    var maxX: Float = -Float.infinity
    var minY: Float = Float.infinity
    var maxY: Float = -Float.infinity
    var minZ: Float = Float.infinity
    var maxZ: Float = -Float.infinity

    let vertices = mesh.vertices
    for i in 0..<mesh.numberOfVertices {
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

  private func calculateBaseSceneBounds() {
    var minX: Float = Float.infinity
    var maxX: Float = -Float.infinity
    var minZ: Float = Float.infinity
    var maxZ: Float = -Float.infinity

    // Use area bounding boxes
    for (_, _, boundingBox) in areaData {
      minX = min(minX, boundingBox.min.x)
      maxX = max(maxX, boundingBox.max.x)
      minZ = min(minZ, boundingBox.min.z)
      maxZ = max(maxZ, boundingBox.max.z)
    }

    // Calculate bounds from actual mesh vertices
    for meshInstance in floorMeshInstances {
      let transform = meshInstance.transformMatrix
      let vertices = meshInstance.mesh.vertices
      for i in 0..<meshInstance.mesh.numberOfVertices {
        let localPos = vec3(
          Float(vertices[i * 3 + 0]),
          Float(vertices[i * 3 + 1]),
          Float(vertices[i * 3 + 2])
        )
        let worldPos = transform * vec4(localPos.x, localPos.y, localPos.z, 1.0)
        minX = min(minX, worldPos.x)
        maxX = max(maxX, worldPos.x)
        minZ = min(minZ, worldPos.z)
        maxZ = max(maxZ, worldPos.z)
      }
    }

    for meshInstance in doorMeshInstances {
      let transform = meshInstance.transformMatrix
      let vertices = meshInstance.mesh.vertices
      for i in 0..<meshInstance.mesh.numberOfVertices {
        let localPos = vec3(
          Float(vertices[i * 3 + 0]),
          Float(vertices[i * 3 + 1]),
          Float(vertices[i * 3 + 2])
        )
        let worldPos = transform * vec4(localPos.x, localPos.y, localPos.z, 1.0)
        minX = min(minX, worldPos.x)
        maxX = max(maxX, worldPos.x)
        minZ = min(minZ, worldPos.z)
        maxZ = max(maxZ, worldPos.z)
      }
    }

    if minX != Float.infinity {
      baseSceneBounds = (minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ)
    }
  }

  func update(deltaTime: Float) {
    // Process keyboard input for pan/zoom
    guard let window = Engine.shared.window else { return }
    let keyboard = window.keyboard

    // Check for speed modifiers
    let isShiftPressed = keyboard.state(of: .leftShift) == .pressed || keyboard.state(of: .rightShift) == .pressed
    let isAltPressed = keyboard.state(of: .leftAlt) == .pressed || keyboard.state(of: .rightAlt) == .pressed

    // Speed multiplier: shift = 3x faster, alt = 0.3x slower
    var speedMultiplier: Float = 1.0
    if isShiftPressed {
      speedMultiplier = 3.0
    } else if isAltPressed {
      speedMultiplier = 0.3
    }

    let panSpeed: Float = 5.0 * deltaTime / cameraZoom * speedMultiplier  // Pan faster when zoomed in

    if keyboard.state(of: .w) == .pressed || keyboard.state(of: .up) == .pressed {
      cameraPan.y -= panSpeed  // Flipped: up moves down
    }
    if keyboard.state(of: .s) == .pressed || keyboard.state(of: .down) == .pressed {
      cameraPan.y += panSpeed  // Flipped: down moves up
    }
    if keyboard.state(of: .a) == .pressed || keyboard.state(of: .left) == .pressed {
      cameraPan.x -= panSpeed  // Flipped: left moves right
    }
    if keyboard.state(of: .d) == .pressed || keyboard.state(of: .right) == .pressed {
      cameraPan.x += panSpeed  // Flipped: right moves left
    }

    // Handle reset animation
    if isResetting {
      resetStartTime += deltaTime
      let progress = min(resetStartTime / resetDuration, 1.0)

      // Use smooth easing for the animation (cubic ease-out)
      let easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress) * (1.0 - progress)

      cameraPan = resetStartPan + (vec2(0, 0) - resetStartPan) * easedProgress
      cameraZoom = resetStartZoom + (0.8 - resetStartZoom) * easedProgress

      if progress >= 1.0 {
        isResetting = false
        cameraPan = vec2(0, 0)
        cameraZoom = 0.8
      }
      return  // Don't process other input during reset
    }

    let zoomSpeed: Float = 1.5 * deltaTime * speedMultiplier
    if keyboard.state(of: .q) == .pressed {
      cameraZoom *= (1.0 + zoomSpeed)
      cameraZoom = min(cameraZoom, 10.0)  // Max zoom
    }
    if keyboard.state(of: .e) == .pressed {
      cameraZoom *= (1.0 - zoomSpeed)
      cameraZoom = max(cameraZoom, 0.1)  // Min zoom
    }
    if keyboard.state(of: .equal) == .pressed {
      cameraZoom *= (1.0 + zoomSpeed)
      cameraZoom = min(cameraZoom, 10.0)  // Max zoom
    }
    if keyboard.state(of: .minus) == .pressed {
      cameraZoom *= (1.0 - zoomSpeed)
      cameraZoom = max(cameraZoom, 0.1)  // Min zoom
    }
  }

  func onKeyPressed(window: Window, key: Keyboard.Key, scancode: Int32, mods: Keyboard.Modifier) {
    switch key {
    case .r:
      // Start reset animation
      guard !isResetting else { return }
      resetStartPan = cameraPan
      resetStartZoom = cameraZoom
      resetStartTime = 0.0
      isResetting = true
    case .semicolon:
      // Cycle forward through room visibility combinations
      cycleRoomVisibility(forward: true)
    case .apostrophe:
      // Cycle backward through room visibility combinations
      cycleRoomVisibility(forward: false)
    default:
      break
    }
  }

  private func cycleRoomVisibility(forward: Bool) {
    let areaCount = areaData.count
    guard areaCount > 0 else { return }

    let maxCombinations = UInt(1 << areaCount)  // 2^areaCount

    switch roomVisibilityMode {
    case .all:
      // Start from all visible (mask = all 1s) when going forward
      // Start from all hidden (mask = 0) when going backward
      if forward {
        roomVisibilityMask = maxCombinations - 1  // All rooms visible
      } else {
        roomVisibilityMask = 0  // All rooms hidden
      }
      roomVisibilityMode = .binary(roomVisibilityMask)
    case .binary(let currentMask):
      if forward {
        // Cycle forward: increment mask, wrap around to 0
        roomVisibilityMask = (currentMask + 1) % maxCombinations
      } else {
        // Cycle backward: decrement mask, wrap around to max
        if currentMask == 0 {
          roomVisibilityMask = maxCombinations - 1
        } else {
          roomVisibilityMask = currentMask - 1
        }
      }
      roomVisibilityMode = .binary(roomVisibilityMask)
    }

    // Debug output
    let visibleAreas = (0..<areaCount).compactMap { index in
      (roomVisibilityMask & (1 << index)) != 0 ? index + 1 : nil
    }
    let binaryString = String(roomVisibilityMask, radix: 2)
    let paddedBinary = String(repeating: "0", count: max(0, areaCount - binaryString.count)) + binaryString
    print("Area visibility: mask=\(paddedBinary) (decimal: \(roomVisibilityMask)/\(maxCombinations-1))")
    print("  Visible areas: \(visibleAreas.isEmpty ? "none" : visibleAreas.map(String.init).joined(separator: ", "))")
  }

  func onScroll(window: Window, xOffset: Double, yOffset: Double) {
    // Use Engine's viewport size (handles VIEWPORT_SCALING correctly)
    let viewportSize = Engine.viewportSize

    // Get mouse position in screen space
    let mousePos = Point(window.mouse.position)

    // Calculate the world position under the mouse before zoom
    let worldPosBefore = screenToWorld(mousePos: mousePos, viewportSize: viewportSize)

    // Apply zoom
    let zoomFactor: Float = 1.0 + Float(yOffset) * 0.1
    cameraZoom *= zoomFactor
    cameraZoom = max(0.1, min(10.0, cameraZoom))  // Clamp zoom

    // Calculate the world position under the mouse after zoom
    let worldPosAfter = screenToWorld(mousePos: mousePos, viewportSize: viewportSize)

    // Adjust pan to keep the mouse point fixed in world space
    let delta = worldPosAfter - worldPosBefore
    cameraPan.x -= delta.x
    cameraPan.y += delta.y  // Flip Y: invert the Y delta to match coordinate system
  }

  /// Convert screen space mouse position to world space coordinates
  private func screenToWorld(mousePos: Point, viewportSize: Size) -> vec2 {
    // Convert screen space to NDC (normalized device coordinates)
    // Screen: (0, 0) = top-left, (width, height) = bottom-right
    // NDC: (-1, -1) = bottom-left, (1, 1) = top-right
    let ndcX = (mousePos.x / viewportSize.width) * 2.0 - 1.0
    // Flip Y: screen Y increases downward, NDC Y increases upward
    // Screen Y=0 (top) → NDC Y=+1, Screen Y=height (bottom) → NDC Y=-1
    let ndcY = 1.0 - (mousePos.y / viewportSize.height) * 2.0

    // Convert NDC to world space using current projection
    // We need to calculate the projection bounds based on current zoom/pan
    if let camera = debugCamera, camera.orthographicWidth > 0 {
      let orthoWidth = camera.orthographicWidth
      let finalAspect = camera.aspect > 0 ? camera.aspect : (viewportSize.width / viewportSize.height)

      // Calculate projection bounds with current zoom
      let zoomedWidth = orthoWidth / cameraZoom
      let left = -zoomedWidth
      let right = zoomedWidth
      let bottom = -zoomedWidth / finalAspect
      let top = zoomedWidth / finalAspect

      // Convert NDC to world space (X and Z for top-down view)
      let worldX = left + (ndcX + 1.0) * (right - left) * 0.5
      let worldZ = bottom + (ndcY + 1.0) * (top - bottom) * 0.5

      // Account for pan offset
      if debugCameraWorldTransform != mat4(1) {
        let rightVector = vec3(
          debugCameraWorldTransform[0].x, debugCameraWorldTransform[0].y, debugCameraWorldTransform[0].z)
        let upVector = vec3(
          debugCameraWorldTransform[1].x, debugCameraWorldTransform[1].y, debugCameraWorldTransform[1].z)
        let panInWorldSpace = rightVector * cameraPan.x + upVector * (-cameraPan.y)
        return vec2(worldX + panInWorldSpace.x, worldZ + panInWorldSpace.z)
      } else {
        return vec2(worldX, worldZ)
      }
    } else {
      // Fallback: use bounds-based projection
      guard let bounds = baseSceneBounds else { return vec2(0, 0) }

      let sceneWidth = bounds.maxX - bounds.minX
      let sceneDepth = bounds.maxZ - bounds.minZ
      let sceneCenterX = (bounds.minX + bounds.maxX) * 0.5
      let sceneCenterZ = (bounds.minZ + bounds.maxZ) * 0.5

      let zoomedWidth = sceneWidth / cameraZoom
      let zoomedDepth = sceneDepth / cameraZoom

      let left = sceneCenterX + cameraPan.x - zoomedWidth * 0.5
      let right = sceneCenterX + cameraPan.x + zoomedWidth * 0.5
      let bottom = sceneCenterZ + cameraPan.y - zoomedDepth * 0.5
      let top = sceneCenterZ + cameraPan.y + zoomedDepth * 0.5

      let worldX = left + (ndcX + 1.0) * (right - left) * 0.5
      let worldZ = bottom + (ndcY + 1.0) * (top - bottom) * 0.5

      return vec2(worldX, worldZ)
    }
  }

  func onMouseButtonPressed(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    isDragging = true
    lastMousePos = Point(window.mouse.position)
  }

  func onMouseButtonReleased(window: Window, button: Mouse.Button, mods: Keyboard.Modifier) {
    guard button == .left else { return }
    isDragging = false
  }

  func onMouseMove(window: Window, x: Double, y: Double) {
    guard isDragging else { return }

    let currentMousePos = Point(Float(x), Float(y))
    let delta = Point(currentMousePos.x - lastMousePos.x, currentMousePos.y - lastMousePos.y)

    // Convert screen space delta to camera space pan
    // cameraPan is in camera space, and the view matrix will transform it correctly
    let panSensitivity: Float = 0.01 / cameraZoom  // Pan faster when zoomed in
    cameraPan.x -= Float(delta.x) * panSensitivity
    cameraPan.y -= Float(delta.y) * panSensitivity

    lastMousePos = currentMousePos
  }

  func draw() {
    // Draw background grid effect
    mapEffect.draw { shader in
      shader.setFloat("uGridScale", value: gridScale)
      shader.setFloat("uGridOpacity", value: gridOpacity)
      shader.setFloat("uVignetteStrength", value: vignetteStrength)
      shader.setFloat("uVignetteRadius", value: vignetteRadius)
      shader.setFloat("uGridCellSize", value: gridCellSize)
      shader.setColor("uBackgroundColor", value: backgroundColor)
      shader.setColor("uGridColor", value: gridColor)
      shader.setFloat("uGridThickness", value: gridThickness)
    }

    guard let context = GraphicsContext.current else {
      promptList.draw()
      return
    }

    // Wait for scene to load
    guard let scene = scene else {
      promptList.draw()
      return
    }

    // Setup rendering on first draw when scene is loaded (when GraphicsContext is guaranteed to be available)
    if !isSetupComplete {
      setupMapRendering()
      isSetupComplete = true
    }

    guard let shaderProgram = mapShaderProgram,
      let renderer = context.renderer as? GLRenderer
    else {
      promptList.draw()
      return
    }

    // Render map directly to screen
    renderMapDirect(shaderProgram: shaderProgram, renderer: renderer, context: context)

    // Draw room labels on top
    drawRoomLabels(context: context, scene: scene)

    // Draw prompt list last
    promptList.draw()
  }

  private func renderMapDirect(shaderProgram: GLProgram, renderer: GLRenderer, context: GraphicsContext) {
    guard !floorMeshInstances.isEmpty || !doorMeshInstances.isEmpty
    else { return }

    // Use Camera_0 if available, otherwise fall back to manual setup
    let projection: mat4
    var view: mat4

    if let camera = debugCamera, camera.orthographicWidth > 0 {
      // Use Camera_0's orthographic projection
      let orthoWidth = camera.orthographicWidth
      let finalAspect = camera.aspect > 0 ? camera.aspect : (context.size.width / context.size.height)

      // Apply zoom to orthographic width
      let zoomedWidth = orthoWidth / cameraZoom
      let left = -zoomedWidth
      let right = zoomedWidth
      let bottom = -zoomedWidth / finalAspect
      let top = zoomedWidth / finalAspect

      projection = GLMath.ortho(left, right, bottom, top, camera.clipPlaneNear, camera.clipPlaneFar)

      // Get view matrix from camera's world transform (inverted)
      if debugCameraWorldTransform != mat4(1) {
        view = inverse(debugCameraWorldTransform)
        // Apply pan offset in camera space
        // For top-down view: right vector (column 0) for X panning, up vector (column 1) for Z panning
        // Column 0 = right (X-axis), Column 1 = up (Z-axis), Column 2 = forward (-Y-axis)
        let rightVector = vec3(
          debugCameraWorldTransform[0].x, debugCameraWorldTransform[0].y, debugCameraWorldTransform[0].z)
        let upVector = vec3(
          debugCameraWorldTransform[1].x, debugCameraWorldTransform[1].y, debugCameraWorldTransform[1].z)
        // Flip Y for correct panning direction
        let panInWorldSpace = rightVector * cameraPan.x + upVector * (-cameraPan.y)
        view = GLMath.translate(view, -panInWorldSpace)
      } else {
        view = mat4(1)
      }
    } else {
      // Fallback: manual orthographic setup
      guard let bounds = baseSceneBounds else { return }

      let sceneWidth = bounds.maxX - bounds.minX
      let sceneDepth = bounds.maxZ - bounds.minZ
      let sceneCenterX = (bounds.minX + bounds.maxX) * 0.5
      let sceneCenterZ = (bounds.minZ + bounds.maxZ) * 0.5

      let zoomedWidth = sceneWidth / cameraZoom
      let zoomedDepth = sceneDepth / cameraZoom
      let panX = sceneCenterX + cameraPan.x
      let panZ = sceneCenterZ + cameraPan.y

      let padding: Float = 5.0
      let left = panX - zoomedWidth * 0.5 - padding
      let right = panX + zoomedWidth * 0.5 + padding
      let bottom = panZ - zoomedDepth * 0.5 - padding
      let top = panZ + zoomedDepth * 0.5 + padding

      projection = GLMath.ortho(left, right, bottom, top, -100.0, 100.0)
      let cameraPos = vec3(panX, 50.0, panZ)
      view = GLMath.lookAt(cameraPos, vec3(panX, 0, panZ), vec3(0, 1, 0))
    }

    // Save current OpenGL state
    let wasDepthEnabled = glIsEnabled(GL_DEPTH_TEST)
    let wasCullEnabled = glIsEnabled(GL_CULL_FACE)
    let wasBlendEnabled = glIsEnabled(GL_BLEND)

    // Set up rendering state
    // Enable depth test so walls render on top of floors
    glEnable(GL_DEPTH_TEST)
    glDepthFunc(GL_LEQUAL)
    glDisable(GL_CULL_FACE)
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)

    // Save viewport
    var viewport: [GLint] = [0, 0, 0, 0]
    glGetIntegerv(GL_VIEWPORT, &viewport)

    // Set viewport to full screen
    let viewportSize = context.size
    glViewport(0, 0, GLsizei(viewportSize.width), GLsizei(viewportSize.height))

    shaderProgram.use()
    shaderProgram.setMat4("projection", value: projection)
    shaderProgram.setMat4("view", value: view)
    shaderProgram.setBool("isWireframe", value: false)
    shaderProgram.setVec2("viewportSize", value: (Float(viewportSize.width), Float(viewportSize.height)))

    // Set SDF tuning parameters
    shaderProgram.setFloat("sdfGradientScale", value: sdfGradientScale)
    shaderProgram.setFloat("sdfEpsilon", value: sdfEpsilon)
    shaderProgram.setFloat("sdfDistanceOffset", value: sdfDistanceOffset)
    shaderProgram.setFloat("sdfDistanceMultiplier", value: sdfDistanceMultiplier)
    shaderProgram.setFloat("strokeThreshold", value: strokeThreshold)
    shaderProgram.setFloat("shadowThreshold", value: shadowThreshold)
    shaderProgram.setBool("debugShowGradient", value: debugShowGradient)

    // Convert hex colors to RGB
    // 36434A -> (0x36/255, 0x43/255, 0x4A/255) = (0.212, 0.263, 0.290)
    let floorFillColor = vec3(0x36 / 255.0, 0x43 / 255.0, 0x4A / 255.0)
    // 5F6261 -> (0x5F/255, 0x62/255, 0x61/255) = (0.373, 0.384, 0.380)
    let floorStrokeColor = vec3(0x5F / 255.0, 0x62 / 255.0, 0x61 / 255.0)
    // 2F3235 -> (0x2F/255, 0x32/255, 0x35/255) = (0.184, 0.196, 0.208)
    let shadowColor = vec3(0x2F / 255.0, 0x32 / 255.0, 0x35 / 255.0)

    // Render floor meshes with shader-based stroke
    for (index, meshInstance) in floorMeshInstances.enumerated() {
      // Check room visibility mask
      if !isRoomVisible(index: index) {
        continue
      }
      shaderProgram.setMat4("model", value: meshInstance.transformMatrix)
      shaderProgram.setVec3("fillColor", value: (floorFillColor.x, floorFillColor.y, floorFillColor.z))
      shaderProgram.setVec3("strokeColor", value: (floorStrokeColor.x, floorStrokeColor.y, floorStrokeColor.z))
      shaderProgram.setVec3("shadowColor", value: (shadowColor.x, shadowColor.y, shadowColor.z))
      shaderProgram.setFloat("shadowSize", value: shadowSize)
      shaderProgram.setFloat("strokeWidth", value: strokeWidth)
      shaderProgram.setFloat("shadowThreshold", value: shadowThreshold)
      shaderProgram.setFloat("shadowStrength", value: shadowStrength)
      shaderProgram.setFloat("shadowFalloff", value: shadowFalloff)
      shaderProgram.setBool("isWireframe", value: false)

      // Calculate mesh bounding box in world space for distance-based inner glow
      let meshBounds = calculateMeshBoundingBox(mesh: meshInstance.mesh, transform: meshInstance.transformMatrix)
      shaderProgram.setVec3("meshBoundsMin", value: (meshBounds.min.x, meshBounds.min.y, meshBounds.min.z))
      shaderProgram.setVec3("meshBoundsMax", value: (meshBounds.max.x, meshBounds.max.y, meshBounds.max.z))

      glBindVertexArray(meshInstance.VAO)
      let indexCount = GLsizei(meshInstance.mesh.faces.count * 3)
      glDrawElements(GL_TRIANGLES, indexCount, GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    // Render border quads (thick lines as geometry) - BEFORE doors so doors render on top
    shaderProgram.setBool("isWireframe", value: false)
    shaderProgram.setFloat("strokeWidth", value: 0.0)  // No shader stroke, we use geometry
    // 5F6261 -> (0x5F/255, 0x62/255, 0x61/255) = (0.373, 0.384, 0.380) - wall color
    let borderStrokeColor = vec3(0x5F / 255.0, 0x62 / 255.0, 0x61 / 255.0)
    shaderProgram.setVec3("fillColor", value: (borderStrokeColor.x, borderStrokeColor.y, borderStrokeColor.z))
    shaderProgram.setVec3("strokeColor", value: (borderStrokeColor.x, borderStrokeColor.y, borderStrokeColor.z))
    shaderProgram.setMat4("model", value: mat4(1))  // Quads are already in world space

    for border in borderLineMeshes {
      glBindVertexArray(border.VAO)
      glDrawElements(GL_TRIANGLES, GLsizei(border.indices.count), GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    // Render door meshes ON TOP of walls (elevated and rendered after walls)
    for (doorIndex, meshInstance) in doorMeshInstances.enumerated() {
      // Check if door should be visible based on connected areas
      if !isDoorVisible(doorIndex: doorIndex) {
        continue
      }
      let nodeName = meshInstance.node?.name ?? ""
      let isLocked = nodeName.contains("frontdoor") || nodeName.lowercased().contains("front")

      // 3E4D86 unlocked, 713D3A locked
      let doorColor =
        isLocked
        ? vec3(0x71 / 255.0, 0x3D / 255.0, 0x3A / 255.0)  // Locked: brown/red
        : vec3(0x3E / 255.0, 0x4D / 255.0, 0x86 / 255.0)  // Unlocked: blue

      // Use adjusted transform if available, otherwise use original
      var doorTransform = doorAdjustedTransforms[doorIndex] ?? meshInstance.transformMatrix
      doorTransform[3][1] += 0.02  // Add Y offset to render on top

      shaderProgram.setMat4("model", value: doorTransform)
      shaderProgram.setVec3("fillColor", value: (doorColor.x, doorColor.y, doorColor.z))
      shaderProgram.setVec3("strokeColor", value: (doorColor.x * 0.7, doorColor.y * 0.7, doorColor.z * 0.7))
      shaderProgram.setVec3("shadowColor", value: (doorColor.x * 0.5, doorColor.y * 0.5, doorColor.z * 0.5))
      shaderProgram.setFloat("shadowSize", value: 2.0)
      shaderProgram.setFloat("strokeWidth", value: 0.0)  // No stroke for doors

      glBindVertexArray(meshInstance.VAO)
      glDrawElements(GL_TRIANGLES, GLsizei(meshInstance.mesh.faces.count * 3), GL_UNSIGNED_INT, nil)
      glBindVertexArray(0)
    }

    // Restore OpenGL state
    glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
    if wasDepthEnabled { glEnable(GL_DEPTH_TEST) } else { glDisable(GL_DEPTH_TEST) }
    if wasCullEnabled { glEnable(GL_CULL_FACE) } else { glDisable(GL_CULL_FACE) }
    if wasBlendEnabled { glEnable(GL_BLEND) } else { glDisable(GL_BLEND) }
  }

  private func drawRoomLabels(context: GraphicsContext, scene: Scene) {
    guard !areaData.isEmpty else { return }

    // Use Camera_0 projection if available, otherwise fall back
    let projection: mat4
    var view: mat4

    if let camera = debugCamera, camera.orthographicWidth > 0 {
      let orthoWidth = camera.orthographicWidth
      let finalAspect = camera.aspect > 0 ? camera.aspect : (context.size.width / context.size.height)
      let zoomedWidth = orthoWidth / cameraZoom
      let left = -zoomedWidth
      let right = zoomedWidth
      let bottom = -zoomedWidth / finalAspect
      let top = zoomedWidth / finalAspect
      projection = GLMath.ortho(left, right, bottom, top, camera.clipPlaneNear, camera.clipPlaneFar)

      if debugCameraWorldTransform != mat4(1) {
        view = inverse(debugCameraWorldTransform)
        // Apply pan offset in camera space (same as in renderMapDirect)
        // Column 0 = right (X-axis), Column 1 = up (Z-axis), Column 2 = forward (-Y-axis)
        let rightVector = vec3(
          debugCameraWorldTransform[0].x, debugCameraWorldTransform[0].y, debugCameraWorldTransform[0].z)
        let upVector = vec3(
          debugCameraWorldTransform[1].x, debugCameraWorldTransform[1].y, debugCameraWorldTransform[1].z)
        // Flip Y for correct panning direction
        let panInWorldSpace = rightVector * cameraPan.x + upVector * (-cameraPan.y)
        view = GLMath.translate(view, -panInWorldSpace)
      } else {
        view = mat4(1)
      }
    } else {
      guard let bounds = baseSceneBounds else { return }
      let sceneWidth = bounds.maxX - bounds.minX
      let sceneDepth = bounds.maxZ - bounds.minZ
      let sceneCenterX = (bounds.minX + bounds.maxX) * 0.5
      let sceneCenterZ = (bounds.minZ + bounds.maxZ) * 0.5
      let zoomedWidth = sceneWidth / cameraZoom
      let zoomedDepth = sceneDepth / cameraZoom
      let panX = sceneCenterX + cameraPan.x
      let panZ = sceneCenterZ + cameraPan.y
      let padding: Float = 5.0
      let left = panX - zoomedWidth * 0.5 - padding
      let right = panX + zoomedWidth * 0.5 + padding
      let bottom = panZ - zoomedDepth * 0.5 - padding
      let top = panZ + zoomedDepth * 0.5 + padding
      projection = GLMath.ortho(left, right, bottom, top, -100.0, 100.0)
      let cameraPos = vec3(panX, 50.0, panZ)
      view = GLMath.lookAt(cameraPos, vec3(panX, 0, panZ), vec3(0, 1, 0))
    }

    let viewportSize = context.size
    let centerX = viewportSize.width / 2.0
    let centerY = viewportSize.height / 2.0

    // Scale font size with zoom (base size * zoom)
    let baseFontSize: Float = 48.0  // Doubled from 24.0
    let scaledFontSize = baseFontSize * cameraZoom
    let labelStyle = TextStyle.itemDescription.withFontSize(scaledFontSize)

    // Draw area labels
    var areaNumber = 1
    for (index, (node, floorNode, boundingBox)) in areaData.enumerated() {
      // Check area visibility mask
      if !isRoomVisible(index: index) {
        areaNumber += 1  // Still increment to keep numbering consistent
        continue
      }
      let position = (boundingBox.min + boundingBox.max) * 0.5
      let worldPos = vec4(position.x, position.y, position.z, 1.0)

      // Transform to clip space
      let clipPos = projection * view * worldPos

      // Convert from clip space [-1, 1] to screen space [0, width/height]
      // Use the same coordinate conversion as the map rendering
      let ndcX = clipPos.x / clipPos.w
      let ndcY = clipPos.y / clipPos.w
      let screenX = centerX + ndcX * (viewportSize.width / 2.0)
      // Convert NDC Y to screen Y: OpenGL clip space has Y up, screen space has Y down
      // Flip Y to match map rendering coordinate system
      // NDC: -1 = bottom, +1 = top
      // Screen: 0 = top, height = bottom (standard screen coordinates)
      // Note: We flip the sign to match the map's coordinate system
      let screenY = centerY + ndcY * (viewportSize.height / 2.0)

      // Get label from Floor node's metadata if available, otherwise use default
      let labelText: String
      if let floorNode = floorNode,
        let metadata = floorNode.metadata?.metadata["label"],
        case .string(let labelString) = metadata
      {
        labelText = labelString
      } else {
        labelText = "Room \(areaNumber)"
      }

      labelText.draw(
        at: Point(screenX, screenY),
        style: labelStyle,
        anchor: .center
      )
      areaNumber += 1
    }
  }

  // MARK: - Helper Functions

  /// Check if an area (room) at the given index should be visible based on the visibility mask
  private func isRoomVisible(index: Int) -> Bool {
    switch roomVisibilityMode {
    case .all:
      return true
    case .binary(let mask):
      return (mask & (1 << index)) != 0
    }
  }

  /// Check if a door should be visible based on its connected areas
  private func isDoorVisible(doorIndex: Int) -> Bool {
    // If door has no connected areas, always show it (e.g., front door)
    guard let connectedAreas = doorToAreas[doorIndex], !connectedAreas.isEmpty else {
      return true
    }

    // Door is visible if ANY of its connected areas are visible
    // This way, if you're viewing area A, you see doors that connect to area A,
    // even if the other connected area (B) is hidden
    return connectedAreas.contains { areaIndex in
      isRoomVisible(index: areaIndex)
    }
  }

  /// Find all nodes containing any of the specified keywords in their names
  private func findNodesContaining(keywords: [String], in node: Node) -> [Node] {
    var result: [Node] = []

    if let nodeName = node.name {
      for keyword in keywords {
        if nodeName.contains(keyword) {
          result.append(node)
          break
        }
      }
    }

    for child in node.children {
      result.append(contentsOf: findNodesContaining(keywords: keywords, in: child))
    }

    return result
  }

  /// Find the Floor node within an area node's children
  private func findFloorNode(in areaNode: Node) -> Node? {
    // Search recursively through children for a node with "Floor" in its name
    if let nodeName = areaNode.name, nodeName.contains("Floor") {
      return areaNode
    }

    for child in areaNode.children {
      if let floorNode = findFloorNode(in: child) {
        return floorNode
      }
    }

    return nil
  }

  /// Calculate world transform for a node by traversing up the hierarchy
  private func calculateNodeWorldTransform(_ node: Node, in scene: Scene) -> mat4 {
    var transform = convertAssimpMatrix(node.transformation)
    var currentNode = node.assimpNode

    while let parent = currentNode.parent {
      let parentTransform = convertAssimpMatrix(parent.transformation)
      transform = parentTransform * transform
      currentNode = parent
    }

    return transform
  }

  /// Convert Assimp matrix to GLMath mat4
  /// Assimp stores matrices in row-major order (a1-a4 is first row)
  private func convertAssimpMatrix(_ matrix: Assimp.Matrix4x4) -> mat4 {
    let row1 = vec4(Float(matrix.a1), Float(matrix.b1), Float(matrix.c1), Float(matrix.d1))
    let row2 = vec4(Float(matrix.a2), Float(matrix.b2), Float(matrix.c2), Float(matrix.d2))
    let row3 = vec4(Float(matrix.a3), Float(matrix.b3), Float(matrix.c3), Float(matrix.d3))
    let row4 = vec4(Float(matrix.a4), Float(matrix.b4), Float(matrix.c4), Float(matrix.d4))
    return mat4(row1, row2, row3, row4)
  }

  /// Calculate bounding box for a node's meshes in world space
  private func calculateNodeBoundingBox(_ node: Node, transform: mat4, in scene: Scene) -> (min: vec3, max: vec3) {
    var minBounds = vec3(Float.infinity, Float.infinity, Float.infinity)
    var maxBounds = vec3(-Float.infinity, -Float.infinity, -Float.infinity)

    // Process all meshes attached to this node
    for meshIndex in node.meshes {
      guard meshIndex < scene.meshes.count else { continue }
      let mesh = scene.meshes[Int(meshIndex)]

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

  /// DEBUG: Recursively print all metadata keys from all nodes in the scene
  private func printAllMetadataKeys(in node: Node, indent: Int) {
    let indentStr = String(repeating: "  ", count: indent)
    let nodeName = node.name ?? "<unnamed>"

    if let metadata = node.metadata {
      print("\(indentStr)Node: \(nodeName)")
      printMetadataKeys(metadata: metadata, indent: indent + 1)
    } else {
      print("\(indentStr)Node: \(nodeName) (no metadata)")
    }

    // Recursively process children
    for child in node.children {
      printAllMetadataKeys(in: child, indent: indent)
    }
  }

  /// DEBUG: Recursively print all keys in a metadata structure
  private func printMetadataKeys(metadata: Assimp.SceneMetadata, indent: Int) {
    let indentStr = String(repeating: "  ", count: indent)

    // Print all top-level keys
    for (index, key) in metadata.keys.enumerated() {
      let value = metadata.values[index]
      print("\(indentStr)Key: '\(key)'")

      // If the value is nested metadata, recurse
      if case .metadata(let nestedMetadata) = value {
        printMetadataKeys(metadata: nestedMetadata, indent: indent + 1)
      }
    }
  }

}
